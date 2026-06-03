import { spawn } from "node:child_process";
import { copyFile, mkdir, readdir, rm, stat } from "node:fs/promises";
import { basename, join } from "node:path";
import { tmpdir } from "node:os";

const [screenshotsDir, outputPath] = process.argv.slice(2);

if (!screenshotsDir || !outputPath) {
  throw new Error("Usage: node create-gif.mjs <screenshots-dir> <output.gif>");
}

const files = (await readdir(screenshotsDir))
  .filter((file) => file.toLowerCase().endsWith(".png"))
  .sort()
  .map((file) => join(screenshotsDir, file));

if (files.length === 0) {
  console.log("No screenshots found; skipping GIF generation");
  process.exit(0);
}

const frameDir = join(tmpdir(), `pharmagrid-gif-${Date.now()}`);
await mkdir(frameDir, { recursive: true });

try {
  for (const [index, file] of files.entries()) {
    await copyFile(file, join(frameDir, `frame-${String(index + 1).padStart(4, "0")}.png`));
  }

  await run("ffmpeg", [
    "-y",
    "-framerate",
    "1",
    "-i",
    join(frameDir, "frame-%04d.png"),
    "-vf",
    "scale=1280:-1:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=white,fps=1",
    "-loop",
    "0",
    outputPath,
  ]);

  const output = await stat(outputPath);
  console.log(`Created ${basename(outputPath)} with ${files.length} screenshots (${output.size} bytes)`);
} finally {
  await rm(frameDir, { recursive: true, force: true });
}

async function run(command, args) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code}`));
      }
    });
  });
}
