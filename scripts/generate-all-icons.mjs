import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

const PROJECT_ROOT = process.cwd();
const USER_UPLOADED_SOURCE = '/Users/shang/.gemini/antigravity/brain/2ab66a49-9794-436e-8de7-09c8da605092/.user_uploaded/media_1790227954492.jpg';
const FALLBACK_SOURCE = path.join(PROJECT_ROOT, 'electron', 'assets', 'logo-source.png');

async function resolveSourcePath() {
  try {
    await fs.access(USER_UPLOADED_SOURCE);
    return USER_UPLOADED_SOURCE;
  } catch {
    return FALLBACK_SOURCE;
  }
}

function getRoundedCornerMask(width, height, radius) {
  return Buffer.from(`
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
      <rect x="0" y="0" width="${width}" height="${height}" rx="${radius}" ry="${radius}" fill="#fff"/>
    </svg>
  `);
}

async function renderRoundedPng(sourceBuffer, size, radiusRatio = 0.2237) {
  const radius = Math.round(size * radiusRatio);
  const mask = getRoundedCornerMask(size, size, radius);
  return sharp(sourceBuffer)
    .resize(size, size, { fit: 'cover' })
    .composite([{ input: mask, blend: 'dest-in' }])
    .png({ quality: 100, compressionLevel: 9 })
    .toBuffer();
}

async function renderSquarePng(sourceBuffer, size, removeAlpha = false) {
  let pipeline = sharp(sourceBuffer).resize(size, size, { fit: 'cover' });
  if (removeAlpha) {
    pipeline = pipeline.removeAlpha();
  }
  return pipeline.png({ quality: 100, compressionLevel: 9 }).toBuffer();
}

function createIco(pngBuffers, sizes) {
  const count = pngBuffers.length;
  const headerLength = 6;
  const dirEntryLength = 16;
  const dirLength = headerLength + count * dirEntryLength;

  let currentOffset = dirLength;
  const entries = [];

  for (let i = 0; i < count; i++) {
    const png = pngBuffers[i];
    const s = sizes[i];
    const entry = Buffer.alloc(16);
    entry.writeUInt8(s >= 256 ? 0 : s, 0);
    entry.writeUInt8(s >= 256 ? 0 : s, 1);
    entry.writeUInt8(0, 2);
    entry.writeUInt8(0, 3);
    entry.writeUInt16LE(1, 4);
    entry.writeUInt16LE(32, 6);
    entry.writeUInt32LE(png.length, 8);
    entry.writeUInt32LE(currentOffset, 12);
    entries.push(entry);
    currentOffset += png.length;
  }

  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(count, 4);

  return Buffer.concat([header, ...entries, ...pngBuffers]);
}

async function createIcns(sourceBuffer) {
  const icnsEntries = [
    ['icp4', 16],
    ['icp5', 32],
    ['icp6', 64],
    ['ic07', 128],
    ['ic08', 256],
    ['ic09', 512],
    ['ic10', 1024],
    ['ic11', 32],
    ['ic12', 64],
    ['ic13', 256],
    ['ic14', 512],
  ];

  const blocks = await Promise.all(
    icnsEntries.map(async ([type, entrySize]) => {
      const png = await renderRoundedPng(sourceBuffer, entrySize);
      const block = Buffer.alloc(8 + png.length);
      block.write(type, 0, 4, 'ascii');
      block.writeUInt32BE(block.length, 4);
      png.copy(block, 8);
      return block;
    }),
  );

  const totalLength = 8 + blocks.reduce((sum, block) => sum + block.length, 0);
  const header = Buffer.alloc(8);
  header.write('icns', 0, 4, 'ascii');
  header.writeUInt32BE(totalLength, 4);

  return Buffer.concat([header, ...blocks], totalLength);
}

async function main() {
  const sourcePath = await resolveSourcePath();
  console.log(`Using source image: ${sourcePath}`);
  const sourceBuffer = await fs.readFile(sourcePath);

  // 1. Save master copy to electron/assets/logo-source.png and public/logo-master.png
  const masterPng = await renderSquarePng(sourceBuffer, 1024, false);
  await fs.mkdir(path.join(PROJECT_ROOT, 'electron', 'assets'), { recursive: true });
  await fs.writeFile(path.join(PROJECT_ROOT, 'electron', 'assets', 'logo-source.png'), masterPng);
  await fs.writeFile(path.join(PROJECT_ROOT, 'public', 'logo-master.png'), masterPng);
  console.log('✓ Master PNG assets saved');

  // 2. Generate public/logo-${size}.png
  const logoSizes = [32, 64, 128, 256, 512];
  for (const size of logoSizes) {
    const roundedPng = await renderRoundedPng(sourceBuffer, size);
    await fs.writeFile(path.join(PROJECT_ROOT, 'public', `logo-${size}.png`), roundedPng);
    console.log(`✓ public/logo-${size}.png created`);
  }

  // 3. Generate public/favicon.png (32x32 and 64x64)
  const faviconPng = await renderRoundedPng(sourceBuffer, 32);
  await fs.writeFile(path.join(PROJECT_ROOT, 'public', 'favicon.png'), faviconPng);
  console.log('✓ public/favicon.png created');

  // 4. Generate public/logo.svg and public/favicon.svg
  const logo512Png = await renderRoundedPng(sourceBuffer, 512);
  const logoSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <image width="512" height="512" href="data:image/png;base64,${logo512Png.toString('base64')}"/>
</svg>
`;
  await fs.writeFile(path.join(PROJECT_ROOT, 'public', 'logo.svg'), logoSvg);
  console.log('✓ public/logo.svg created');

  const favicon128Png = await renderRoundedPng(sourceBuffer, 128);
  const faviconSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <image width="128" height="128" href="data:image/png;base64,${favicon128Png.toString('base64')}"/>
</svg>
`;
  await fs.writeFile(path.join(PROJECT_ROOT, 'public', 'favicon.svg'), faviconSvg);
  console.log('✓ public/favicon.svg created');

  // 5. Generate public/icons/icon-${size}x${size}.png and .svg for PWA
  const pwaSizes = [72, 96, 128, 144, 152, 192, 384, 512];
  await fs.mkdir(path.join(PROJECT_ROOT, 'public', 'icons'), { recursive: true });
  for (const size of pwaSizes) {
    const pwaPng = await renderSquarePng(sourceBuffer, size, false);
    await fs.writeFile(path.join(PROJECT_ROOT, 'public', 'icons', `icon-${size}x${size}.png`), pwaPng);

    const pwaSvg = `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <image width="${size}" height="${size}" href="data:image/png;base64,${pwaPng.toString('base64')}"/>
</svg>
`;
    await fs.writeFile(path.join(PROJECT_ROOT, 'public', 'icons', `icon-${size}x${size}.svg`), pwaSvg);
    console.log(`✓ public/icons/icon-${size}x${size}.png & .svg created`);
  }

  // 6. Generate electron desktop assets
  const macosPng = await renderRoundedPng(sourceBuffer, 1024);
  await fs.writeFile(path.join(PROJECT_ROOT, 'electron', 'assets', 'logo-macos.png'), macosPng);
  console.log('✓ electron/assets/logo-macos.png created');

  const macosIcns = await createIcns(sourceBuffer);
  await fs.writeFile(path.join(PROJECT_ROOT, 'electron', 'assets', 'logo-macos.icns'), macosIcns);
  console.log('✓ electron/assets/logo-macos.icns created');

  const icoSizes = [16, 24, 32, 48, 64, 128, 256];
  const icoPngBuffers = await Promise.all(icoSizes.map((s) => renderRoundedPng(sourceBuffer, s)));
  const windowsIco = createIco(icoPngBuffers, icoSizes);
  await fs.writeFile(path.join(PROJECT_ROOT, 'electron', 'assets', 'logo-windows.ico'), windowsIco);
  console.log('✓ electron/assets/logo-windows.ico created');

  // 7. Generate iOS app icons
  const iosIconDir = path.join(PROJECT_ROOT, 'mobile', 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');
  try {
    const contentsJsonPath = path.join(iosIconDir, 'Contents.json');
    const contentsJsonRaw = await fs.readFile(contentsJsonPath, 'utf8');
    const contents = JSON.parse(contentsJsonRaw);

    for (const image of contents.images) {
      const [wStr, hStr] = image.size.split('x');
      const baseWidth = Number.parseFloat(wStr);
      const scaleMultiplier = Number.parseInt(image.scale.replace('x', ''), 10) || 1;
      const targetDimension = Math.round(baseWidth * scaleMultiplier);

      // iOS app icons must not have alpha channel
      const iosPng = await renderSquarePng(sourceBuffer, targetDimension, true);
      await fs.writeFile(path.join(iosIconDir, image.filename), iosPng);
      console.log(`✓ iOS ${image.filename} (${targetDimension}x${targetDimension}) created`);
    }
  } catch (err) {
    console.warn('Skipping iOS icon update (directory or Contents.json not accessible):', err.message);
  }

  console.log('\nAll app icons generated successfully!');
}

main().catch((err) => {
  console.error('Failed to generate icons:', err);
  process.exit(1);
});
