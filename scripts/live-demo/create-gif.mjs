import { createReadStream, createWriteStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { basename, join } from "node:path";

const [screenshotsDir, outputPath] = process.argv.slice(2);

if (!screenshotsDir || !outputPath) {
  throw new Error("Usage: node create-gif.mjs <screenshots-dir> <output.gif>");
}

const [{ default: GIFEncoder }, { PNG }] = await Promise.all([
  import("gifencoder"),
  import("pngjs"),
]);

const files = (await readdir(screenshotsDir))
  .filter((file) => file.toLowerCase().endsWith(".png"))
  .sort()
  .map((file) => join(screenshotsDir, file));

if (files.length === 0) {
  console.log("No screenshots found; skipping GIF generation");
  process.exit(0);
}

const frames = [];
for (const file of files) {
  const png = await readPng(file);
  frames.push({ file, png });
}

const width = frames[0].png.width;
const height = frames[0].png.height;
const compatibleFrames = frames.filter((frame) => frame.png.width === width && frame.png.height === height);

const encoder = new GIFEncoder(width, height);
const outputStream = createWriteStream(outputPath);
const finished = new Promise((resolve, reject) => {
  outputStream.on("finish", resolve);
  outputStream.on("error", reject);
});
encoder.createReadStream().pipe(outputStream);
encoder.start();
encoder.setRepeat(0);
encoder.setDelay(1200);
encoder.setQuality(12);

for (const frame of compatibleFrames) {
  encoder.addFrame(frame.png.data);
}

encoder.finish();
await finished;

const output = await stat(outputPath);
console.log(
  `Created ${basename(outputPath)} with ${compatibleFrames.length}/${frames.length} screenshots (${output.size} bytes)`,
);

async function readPng(path) {
  return await new Promise((resolve, reject) => {
    createReadStream(path)
      .pipe(new PNG())
      .on("parsed", function () {
        resolve(this);
      })
      .on("error", reject);
  });
}
