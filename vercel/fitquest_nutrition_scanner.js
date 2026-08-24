(() => {
  const TESSERACT_URL =
    'https://cdn.jsdelivr.net/npm/tesseract.js@7/dist/tesseract.min.js';

  let tesseractScriptPromise = null;
  let workerPromise = null;

  function loadTesseract() {
    if (window.Tesseract) return Promise.resolve(window.Tesseract);
    if (tesseractScriptPromise) return tesseractScriptPromise;

    tesseractScriptPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = TESSERACT_URL;
      script.async = true;
      script.onload = () => resolve(window.Tesseract);
      script.onerror = () =>
        reject(new Error('Could not load the nutrition scanner.'));
      document.head.appendChild(script);
    });

    return tesseractScriptPromise;
  }

  async function getWorker() {
    if (!workerPromise) {
      workerPromise = (async () => {
        const Tesseract = await loadTesseract();
        return Tesseract.createWorker('eng', 1, {
          logger: () => {},
        });
      })().catch((error) => {
        workerPromise = null;
        throw error;
      });
    }

    return workerPromise;
  }

  function chooseImage() {
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';

      // On mobile browsers this strongly prefers the rear camera.
      input.setAttribute('capture', 'environment');
      input.style.position = 'fixed';
      input.style.left = '-9999px';
      document.body.appendChild(input);

      let finished = false;

      const cleanup = () => {
        if (input.parentNode) input.parentNode.removeChild(input);
      };

      const finish = (file) => {
        if (finished) return;
        finished = true;
        cleanup();
        resolve(file || null);
      };

      input.addEventListener(
        'change',
        () => finish(input.files && input.files.length ? input.files[0] : null),
        { once: true },
      );

      input.addEventListener('cancel', () => finish(null), { once: true });
      input.click();
    });
  }

  function loadImage(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();

      img.onload = () => {
        URL.revokeObjectURL(url);
        resolve(img);
      };

      img.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error('Could not read the captured photo.'));
      };

      img.src = url;
    });
  }

  async function prepareImage(file) {
    const img = await loadImage(file);

    const maxWidth = 1600;
    const maxHeight = 2200;
    const scale = Math.min(
      1,
      maxWidth / img.naturalWidth,
      maxHeight / img.naturalHeight,
    );

    const width = Math.max(1, Math.round(img.naturalWidth * scale));
    const height = Math.max(1, Math.round(img.naturalHeight * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;

    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, width, height);

    // Nutrition panels are generally dark text on a light background.
    // Grayscale + modest contrast helps OCR without expensive CV processing.
    const imageData = ctx.getImageData(0, 0, width, height);
    const data = imageData.data;

    for (let i = 0; i < data.length; i += 4) {
      const gray =
        0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
      const contrasted = Math.max(
        0,
        Math.min(255, (gray - 128) * 1.35 + 128),
      );

      data[i] = contrasted;
      data[i + 1] = contrasted;
      data[i + 2] = contrasted;
    }

    ctx.putImageData(imageData, 0, 0);
    return canvas;
  }

  function parseNumber(value) {
    if (!value) return null;
    const number = Number(String(value).replace(',', '.'));
    return Number.isFinite(number) ? number : null;
  }

  function fractionToNumber(raw) {
    if (!raw) return null;

    const unicodeFractions = {
      '¼': 0.25,
      '½': 0.5,
      '¾': 0.75,
      '⅓': 1 / 3,
      '⅔': 2 / 3,
      '⅛': 0.125,
      '⅜': 0.375,
      '⅝': 0.625,
      '⅞': 0.875,
    };

    const value = raw.trim();

    if (unicodeFractions[value] != null) {
      return unicodeFractions[value];
    }

    const mixedUnicode = value.match(/^(\d+)\s*([¼½¾⅓⅔⅛⅜⅝⅞])$/);
    if (mixedUnicode) {
      return Number(mixedUnicode[1]) + unicodeFractions[mixedUnicode[2]];
    }

    if (/^\d+(?:\.\d+)?$/.test(value)) return Number(value);

    const simple = value.match(/^(\d+)\/(\d+)$/);
    if (simple) {
      const denominator = Number(simple[2]);
      return denominator ? Number(simple[1]) / denominator : null;
    }

    const mixed = value.match(/^(\d+)\s+(\d+)\/(\d+)$/);
    if (mixed) {
      const denominator = Number(mixed[3]);
      return denominator
        ? Number(mixed[1]) + Number(mixed[2]) / denominator
        : null;
    }

    return null;
  }

  function normalizeUnit(raw) {
    const unit = (raw || '').toLowerCase().replace(/\./g, '');

    const units = {
      g: 'g',
      gram: 'g',
      grams: 'g',
      oz: 'oz',
      ounce: 'oz',
      ounces: 'oz',
      cup: 'cup',
      cups: 'cup',
      tbsp: 'tbsp',
      tablespoon: 'tbsp',
      tablespoons: 'tbsp',
      tsp: 'tsp',
      teaspoon: 'tsp',
      teaspoons: 'tsp',
      piece: 'piece',
      pieces: 'piece',
      slice: 'slice',
      slices: 'slice',
      bottle: 'bottle',
      bottles: 'bottle',
      can: 'can',
      cans: 'can',
      package: 'package',
      packages: 'package',
      serving: 'serving',
      servings: 'serving',
      bar: 'piece',
      bars: 'piece',
      cookie: 'piece',
      cookies: 'piece',
      pouch: 'piece',
      pouches: 'piece',
      packet: 'piece',
      packets: 'piece',
    };

    return units[unit] || null;
  }

  function parseServingSize(text) {
    const normalized = text
      .replace(/[|]/g, 'I')
      .replace(/[ \t]+/g, ' ')
      .replace(/\r?\n/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();

    const servingMatch = normalized.match(
      /serving\s*s[i1l]ze\s*:?\s*(.{0,100})/i,
    );

    if (!servingMatch) {
      return { amount: null, unit: null };
    }

    const servingText = servingMatch[1];

    // Mirror the serving units supported by FitQuest.
    // Prefer the label's actual serving unit whenever it is one the app knows.
    const supportedUnitPattern =
      '(g|grams?|oz|ounces?|cups?|tbsp|tablespoons?|tsp|teaspoons?|pieces?|slices?|bottles?|cans?|packages?|servings?)';

    const amountPattern =
      '(\\d+\\s+\\d+\\/\\d+|\\d+\\/\\d+|\\d+\\s*[¼½¾⅓⅔⅛⅜⅝⅞]|[¼½¾⅓⅔⅛⅜⅝⅞]|\\d+(?:[.,]\\d+)?)';

    // First try the primary serving description before any parenthetical weight.
    // Examples:
    //   "2 tbsp (32g)"     -> 2 tbsp
    //   "2/3 cup (55g)"   -> 0.667 cup
    //   "1 cup (240mL)"   -> 1 cup
    //   "28 g"            -> 28 g
    const primaryText = servingText.split('(')[0].trim();

    const supportedMatch = primaryText.match(
      new RegExp(amountPattern + '\\s*' + supportedUnitPattern + '\\b', 'i'),
    );

    if (supportedMatch) {
      const amount = fractionToNumber(supportedMatch[1].replace(',', '.'));
      const unit = normalizeUnit(supportedMatch[2]);

      if (amount != null && unit != null) {
        return { amount, unit };
      }
    }

    // If the serving is a count of an unsupported food noun such as
    // "1 bar", "2 cookies", or "15 chips", represent that count using
    // FitQuest's generic "piece" unit rather than hardcoding food names.
    const genericCountMatch = primaryText.match(
      new RegExp(
        '^\\s*' + amountPattern + '\\s+([A-Za-z][A-Za-z\\-]*)\\b',
        'i',
      ),
    );

    if (genericCountMatch) {
      const amount = fractionToNumber(genericCountMatch[1].replace(',', '.'));
      const unknownUnit = genericCountMatch[2].toLowerCase();

      // Avoid converting measurement-looking abbreviations to pieces.
      const looksLikeMeasurement =
        /^(ml|l|mg|kg|fl|fluid)$/i.test(unknownUnit);

      if (amount != null && !looksLikeMeasurement) {
        return {
          amount,
          unit: 'piece',
        };
      }
    }

    // Final fallback: use a standardized parenthetical gram/ounce weight when
    // the primary serving description could not be represented by FitQuest.
    const weightMatch = servingText.match(
      /\(\s*(\d+(?:[.,]\d+)?)\s*(g|grams?|oz|ounces?)\s*\)/i,
    );

    if (weightMatch) {
      return {
        amount: parseNumber(weightMatch[1]),
        unit: normalizeUnit(weightMatch[2]),
      };
    }

    return { amount: null, unit: null };
  }

  function extractNutrition(text) {
    const normalized = text
      .replace(/[|]/g, 'I')
      .replace(/[ \t]+/g, ' ');

    const flattened = normalized
      .replace(/\r?\n/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();

    const findValue = (patterns) => {
      for (const pattern of patterns) {
        const match = flattened.match(pattern);
        if (match) {
          const value = parseNumber(match[1]);
          if (value !== null) return value;
        }
      }
      return null;
    };

    const serving = parseServingSize(normalized);

    return {
      calories: findValue([
        /\bcalor[i1l]es?\s*[:\-]?\s*(\d+(?:[.,]\d+)?)/i,
      ]),
      fat: findValue([
        /\btotal\s+fat\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /\bfat\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
      ]),
      carbs: findValue([
        /\btotal\s+carbo\s*hydrate\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /\btotal\s+carbohydrate\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /\btotal\s+carbohydrates\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /\btotal\s+carbs?\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /\bcarbo\s*hydrate\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /\bcarbohydrates?\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
      ]),
      protein: findValue([
        /\bprote[i1l]n\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
      ]),
      servingAmount: serving.amount,
      servingUnit: serving.unit,
      cancelled: false,

      // Temporary troubleshooting data. Keeping this in the returned object
      // costs essentially nothing and lets us inspect OCR output later if a
      // specific label still fails.
      ocrText: normalized,
    };
  }

  window.fitQuestScanNutritionLabel = async function () {
    const file = await chooseImage();

    if (!file) {
      return JSON.stringify({ cancelled: true });
    }

    const [worker, image] = await Promise.all([
      getWorker(),
      prepareImage(file),
    ]);

    const result = await worker.recognize(image);
    return JSON.stringify(extractNutrition(result.data.text || ''));
  };

  // Pre-warm after FitQuest has had time to render. This does not block the UI.
  window.addEventListener('load', () => {
    window.setTimeout(() => {
      getWorker().catch(() => {});
    }, 1500);
  });
})();
