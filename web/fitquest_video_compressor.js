/* FitQuest browser-side form video compression. Video-only (audio is removed).
 * Requires canvas.captureStream and MediaRecorder. Encodes in real time.
 */
window.fitQuestCompressVideo = async function (inputBytes, inputMime, maxSeconds) {
  if (typeof MediaRecorder === 'undefined' || !HTMLCanvasElement.prototype.captureStream) {
    throw new Error('Video compression is not supported by this browser.');
  }
  const mimeTypes = [
    'video/mp4;codecs=avc1.42E01E', 'video/mp4',
    'video/webm;codecs=vp8', 'video/webm'
  ];
  const outputMime = mimeTypes.find(t => MediaRecorder.isTypeSupported(t));
  if (!outputMime) throw new Error('This browser cannot encode MP4 or WebM videos.');
  const sourceBlob = new Blob([inputBytes], {type: inputMime || 'video/quicktime'});
  const sourceUrl = URL.createObjectURL(sourceBlob);
  const video = document.createElement('video');
  video.preload = 'auto'; video.muted = true; video.playsInline = true;
  video.setAttribute('playsinline', '');
  video.src = sourceUrl;
  let stream, recorder;
  try {
    await new Promise((resolve, reject) => {
      video.onloadedmetadata = resolve;
      video.onerror = () => reject(new Error('The selected video cannot be decoded by this browser.'));
      video.load();
    });
    if (!Number.isFinite(video.duration) || video.duration <= 0)
      throw new Error('Could not determine video duration.');
    if (video.duration > maxSeconds)
      throw new Error(`Video is ${Math.ceil(video.duration)} seconds. Maximum is ${maxSeconds} seconds.`);
    const scale = Math.min(1, 1280 / video.videoWidth, 720 / video.videoHeight);
    const width = Math.max(2, Math.floor(video.videoWidth * scale / 2) * 2);
    const height = Math.max(2, Math.floor(video.videoHeight * scale / 2) * 2);
    const canvas = document.createElement('canvas');
    canvas.width = width; canvas.height = height;
    const ctx = canvas.getContext('2d', {alpha: false});
    if (!ctx) throw new Error('Unable to initialize video encoder canvas.');
    stream = canvas.captureStream(24);
    const chunks = [];
    recorder = new MediaRecorder(stream, {mimeType: outputMime, videoBitsPerSecond: 850000});
    const recorded = new Promise((resolve, reject) => {
      recorder.ondataavailable = e => { if (e.data && e.data.size) chunks.push(e.data); };
      recorder.onerror = () => reject(new Error('Video encoding failed.'));
      recorder.onstop = () => resolve(new Blob(chunks, {type: recorder.mimeType || outputMime}));
    });
    let frameId;
    const draw = () => {
      if (!video.paused && !video.ended) {
        ctx.drawImage(video, 0, 0, width, height);
        frameId = requestAnimationFrame(draw);
      }
    };
    video.currentTime = 0;
    recorder.start(1000);
    try {
      await video.play();
      draw();
      await new Promise((resolve, reject) => {
        video.onended = resolve;
        video.onerror = () => reject(new Error('Video playback failed during compression.'));
      });
    } finally {
      if (frameId) cancelAnimationFrame(frameId);
      video.pause();
      if (recorder.state !== 'inactive') recorder.stop();
    }
    const result = await recorded;
    if (!result.size) throw new Error('Compression produced an empty video.');
    if (result.size >= sourceBlob.size)
      throw new Error('Compression did not reduce this video size. Try a shorter or higher-quality source.');
    const outputBytes = new Uint8Array(await result.arrayBuffer());
    return {bytes: outputBytes, mimeType: result.type.split(';')[0], originalSize: sourceBlob.size, compressedSize: result.size};
  } finally {
    video.pause(); video.removeAttribute('src'); video.load();
    if (stream) stream.getTracks().forEach(t => t.stop());
    URL.revokeObjectURL(sourceUrl);
  }
};
