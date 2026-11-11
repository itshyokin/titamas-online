// Exports the Saturn engine's built-in item icons (16 × 16 pixel art drawn in code, in
// hd2dengine/src/art/itemIcons.ts) as PNGs for Titamas:
//   assets/icons/items/<name>.png  and  assets/icons/items/icons.json (picker groups + names)
// Items use them as "icon": "builtin:<name>" (ItemIcon; Database → Items → Icon), with an
// optional "icon_tint" recolour done the same way as Saturn's tintCanvas.
//
// Usage (from the titamas-online folder; needs Node 18+, fetches esbuild with npx):
//   node tools/art/export_saturn_icons.mjs <path to hd2dengine>
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import { pathToFileURL } from "node:url";

const saturn = process.argv[2];
if (!saturn || !fs.existsSync(path.join(saturn, "src/art/itemIcons.ts"))) {
	console.error("Usage: node tools/art/export_saturn_icons.mjs <path to hd2dengine>");
	process.exit(1);
}
const out = path.resolve("assets/icons/items");
fs.mkdirSync(out, { recursive: true });

// Bundle a tiny entry that draws every icon into raw RGBA.
const work = fs.mkdtempSync(path.join(os.tmpdir(), "saturn-icons-"));
const entry = path.join(work, "entry.ts");
const icons = path.resolve(saturn, "src/art/itemIcons.ts").replaceAll("\\", "/");
const pixel = path.resolve(saturn, "src/core/pixel.ts").replaceAll("\\", "/");
fs.writeFileSync(entry, `
import { ITEM_ICONS, iconGroups } from "${icons}";
import { Pix } from "${pixel}";
export function draw(name: string): Uint8ClampedArray {
	const p = new Pix(16, 16);
	ITEM_ICONS[name].draw(p);
	p.outline("#1a1420");
	return p.d;
}
export const groups = iconGroups();
export const names: Record<string, string> = Object.fromEntries(Object.entries(ITEM_ICONS).map(([k, v]) => [k, v.name]));
`);
const bundle = path.join(work, "bundle.mjs");
execFileSync("npx", ["--yes", "esbuild@0.24.0", entry, "--bundle", "--format=esm", "--platform=node", "--outfile=" + bundle, "--log-level=warning"], { stdio: "inherit", shell: process.platform === "win32" });
const mod = await import(pathToFileURL(bundle).href);

// Minimal PNG writer (RGBA, no filter).
const CRC = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc32 = (buf) => { let c = -1; for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => {
	const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
	const td = Buffer.concat([Buffer.from(type), data]);
	const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
	return Buffer.concat([len, td, crc]);
};
function png(rgba, w, h) {
	const raw = Buffer.alloc((w * 4 + 1) * h);
	for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
	return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

let n = 0;
for (const name of Object.keys(mod.names)) {
	fs.writeFileSync(path.join(out, name + ".png"), png(mod.draw(name), 16, 16));
	n++;
}
const groups = mod.groups.map(([g, list]) => [g, list.map((id) => [id, mod.names[id]])]);
fs.writeFileSync(path.join(out, "icons.json"), JSON.stringify({ size: 16, groups }, null, "\t") + "\n");
fs.rmSync(work, { recursive: true, force: true });
console.log(`Wrote ${n} icons to ${out}`);
