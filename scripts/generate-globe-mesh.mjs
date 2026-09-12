// Regenerate the bundled, public map geometry from the original web dashboard.
// Usage: node scripts/generate-globe-mesh.mjs /path/to/loslo-dashboard
// No dashboard data or credentials are read. The Mac app needs neither Node nor a server.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const webRoot = path.resolve(process.argv[2] ?? '../loslo-dashboard');
const requireWeb = createRequire(path.join(webRoot, 'package.json'));
const { feature } = requireWeb('topojson-client');
const iso = requireWeb('iso-3166-1');
const { geoContains, geoBounds, geoCentroid, geoArea } = await import(
  pathToFileURL(path.join(webRoot, 'node_modules/d3-geo/src/index.js'))
);
const output = fileURLToPath(new URL('../Sources/Resources/', import.meta.url));
const topo = JSON.parse(fs.readFileSync(path.join(webRoot, 'public/world-countries-110m.json')));
const features = feature(topo, topo.objects.countries).features.filter(f => Number(f.id) !== 10);
const regions = features.map(geometry => ({ geometry, bounds: geoBounds(geometry) }));
const norm = v => { const length = Math.hypot(...v); return v.map(x => x / length); };
const dot = (a, b) => a.reduce((sum, x, i) => sum + x * b[i], 0);
const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];

// The same Goldberg tessellation, frequency and cell gaps as components/Globe.tsx.
const frequency = 60, shrink = 0.86, t = (1 + Math.sqrt(5)) / 2;
const base = [[-1,t,0],[1,t,0],[-1,-t,0],[1,-t,0],[0,-1,t],[0,1,t],
  [0,-1,-t],[0,1,-t],[t,0,-1],[t,0,1],[-t,0,-1],[-t,0,1]].map(norm);
const faces = [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],
  [11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
  [4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]];
const vertices = [], indices = new Map(), around = [], centers = [];
function addVertex(v) {
  const unit = norm(v), key = unit.map(x => x.toFixed(5)).join(',');
  if (indices.has(key)) return indices.get(key);
  const index = vertices.length;
  indices.set(key, index); vertices.push(unit); around.push([]);
  return index;
}
function addTriangle(a, b, c) {
  const center = norm(vertices[a].map((x, i) => x + vertices[b][i] + vertices[c][i]));
  const index = centers.length; centers.push(center);
  for (const vertex of [a, b, c]) around[vertex].push(index);
}
for (const [a, b, c] of faces) {
  const grid = [];
  for (let i = 0; i <= frequency; i++) {
    grid[i] = [];
    for (let j = 0; j <= frequency - i; j++) {
      const k = frequency - i - j;
      grid[i][j] = addVertex(base[a].map((x, axis) =>
        (x*k + base[b][axis]*i + base[c][axis]*j) / frequency));
    }
  }
  for (let i = 0; i < frequency; i++) for (let j = 0; j < frequency-i; j++) {
    addTriangle(grid[i][j], grid[i+1][j], grid[i][j+1]);
    if (j < frequency-i-1) addTriangle(grid[i+1][j], grid[i+1][j+1], grid[i][j+1]);
  }
}
const cells = vertices.flatMap((center, index) => {
  const lon = Math.atan2(center[2], center[0]) * 180 / Math.PI;
  const lat = Math.asin(center[1]) * 180 / Math.PI;
  const land = regions.some(({geometry, bounds:[[west,south],[east,north]]}) =>
    lat >= south && lat <= north && (west <= east ? lon >= west && lon <= east : lon >= west || lon <= east)
    && geoContains(geometry, [lon, lat]));
  if (!land) return [];
  const helper = Math.abs(center[1]) < 0.9 ? [0,1,0] : [1,0,0];
  const e1 = norm(cross(helper, center)), e2 = cross(center, e1);
  const polygon = around[index].map(i => centers[i])
    .sort((a,b) => Math.atan2(dot(a,e2), dot(a,e1)) - Math.atan2(dot(b,e2), dot(b,e1)))
    .map(v => norm(v.map((x, i) => center[i] + (x-center[i])*shrink)));
  return [{center, polygon}];
});
if (vertices.length !== 36002 || cells.length < 7000 || cells.length > 13000) {
  throw new Error('Unexpected globe geometry');
}
// LSG1 + UInt32 count; each cell: Float32 xyz, UInt8 corner count, Float32 xyz per corner.
const mesh = Buffer.alloc(8 + cells.reduce((size, c) => size + 13 + c.polygon.length * 12, 0));
mesh.write('LSG1'); mesh.writeUInt32LE(cells.length, 4);
let offset = 8;
const vector = v => { for (const x of v) { mesh.writeFloatLE(x, offset); offset += 4; } };
for (const cell of cells) {
  vector(cell.center); mesh.writeUInt8(cell.polygon.length, offset++);
  cell.polygon.forEach(vector);
}
fs.writeFileSync(path.join(output, 'globe-mesh.bin'), mesh);

const centroids = {};
for (const f of features) {
  const code = iso.whereNumeric(String(f.id).padStart(3, '0'))?.alpha2;
  if (!code) continue;
  const mainland = f.geometry.type === 'MultiPolygon'
    ? f.geometry.coordinates.map(coordinates => ({type:'Polygon',coordinates}))
      .sort((a,b) => geoArea(b)-geoArea(a))[0] : f;
  centroids[code] = geoCentroid(mainland).map(x => Number(x.toFixed(5)));
}
fs.writeFileSync(path.join(output, 'globe-centroids.json'), JSON.stringify(centroids));
console.log(`Bundled ${cells.length} land cells and ${Object.keys(centroids).length} country positions (${mesh.length} bytes).`);
