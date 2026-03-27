const fs = require('fs');
const content = fs.readFileSync('d:\\fccc\\apppp', 'utf8');
const lines = content.split(/\r?\n/);
let fileCount = 0;
for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() === '================================================' &&
        i + 2 < lines.length &&
        lines[i+1].startsWith('FILE: ') &&
        lines[i+2].trim() === '================================================') {
        fileCount++;
    }
}
console.log('Files to extract:', fileCount);
