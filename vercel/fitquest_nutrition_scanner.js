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
    const value = raw.trim();

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
    };

    return units[unit] || null;
  }

  function parseServingSize(text) {
    const lines = text
      .split(/\r?\n/)
      .map((line) => line.replace(/\s+/g, ' ').trim())
      .filter(Boolean);

    const line =
      lines.find((value) => /serving\s*size/i.test(value)) ||
      lines.find((value) => /\bserving\b/i.test(value));

    if (!line) return { amount: null, unit: null };

    const cleaned = line
      .replace(/^.*?serving\s*size\s*:?\s*/i, '')
      .replace(/^.*?serving\s*:?\s*/i, '');

    const unitPattern =
      '(g|grams?|oz|ounces?|cups?|tbsp|tablespoons?|tsp|teaspoons?|pieces?|slices?|bottles?|cans?|packages?|servings?)';

    // Prefer the consumer-facing serving, e.g. "2/3 cup" in
    // "Serving size 2/3 cup (55g)".
    const beforeParen = cleaned.split('(')[0];
    let match = beforeParen.match(
      new RegExp(
        '(\\d+\\s+\\d+\\/\\d+|\\d+\\/\\d+|\\d+(?:\\.\\d+)?)\\s*' +
          unitPattern +
          '\\b',
        'i',
      ),
    );

    // If the first description is something unsupported like "15 chips",
    // use the standardized parenthetical weight, usually "(28g)".
    if (!match) {
      match = cleaned.match(
        new RegExp(
          '(\\d+\\s+\\d+\\/\\d+|\\d+\\/\\d+|\\d+(?:\\.\\d+)?)\\s*' +
            unitPattern +
            '\\b',
          'i',
        ),
      );
    }

    if (!match) return { amount: null, unit: null };

    return {
      amount: fractionToNumber(match[1]),
      unit: normalizeUnit(match[2]),
    };
  }

  function extractNutrition(text) {
    const normalized = text
      .replace(/[|]/g, 'I')
      .replace(/[ \t]+/g, ' ');

    const lines = normalized
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);

    const findValue = (patterns) => {
      for (const line of lines) {
        for (const pattern of patterns) {
          const match = line.match(pattern);
          if (match) {
            const value = parseNumber(match[1]);
            if (value !== null) return value;
          }
        }
      }
      return null;
    };

    const serving = parseServingSize(normalized);

    return {
      calories: findValue([
        /\bcalories?\s*[:\-]?\s*(\d+(?:[.,]\d+)?)/i,
      ]),
      fat: findValue([
        /\btotal\s+fat\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /^\s*fat\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
      ]),
      carbs: findValue([
        /\btotal\s+carbohydrate\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /\btotal\s+carbs?\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
        /^\s*carbohydrates?\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
      ]),
      protein: findValue([
        /\bprotein\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*g\b/i,
      ]),
      servingAmount: serving.amount,
      servingUnit: serving.unit,
      cancelled: false,
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
