import fs from 'node:fs/promises';
import sharp from 'sharp';

const size = 1024;
const assetsDir = 'electron/assets';
const sourcePath = 'electron/assets/logo-source.png';
const iconPath = 'electron/assets/logo-macos.png';
const icnsPath = 'electron/assets/logo-macos.icns';

function getRoundedCornerMask(width, height, radius) {
  return Buffer.from(`
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
      <rect x="0" y="0" width="${width}" height="${height}" rx="${radius}" ry="${radius}" fill="#fff"/>
    </svg>
  `);
}

async function renderPng(sourceBuffer, entrySize) {
  const radius = Math.round(entrySize * 0.2237);
  const mask = getRoundedCornerMask(entrySize, entrySize, radius);
  return sharp(sourceBuffer)
    .resize(entrySize, entrySize, { fit: 'cover' })
    .composite([{ input: mask, blend: 'dest-in' }])
    .png({ quality: 100, compressionLevel: 9 })
    .toBuffer();
}

await fs.mkdir(assetsDir, { recursive: true });
const sourceBuffer = await fs.readFile(sourcePath);
await fs.writeFile(iconPath, await renderPng(sourceBuffer, size));

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
    const png = await renderPng(sourceBuffer, entrySize);
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

await fs.writeFile(icnsPath, Buffer.concat([header, ...blocks], totalLength));
console.log('Successfully generated macOS icon assets.');
