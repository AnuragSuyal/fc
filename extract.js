const fs = require('fs');
const path = require('path');

function extractProject() {
    const inFile = 'd:\\fccc\\apppp';
    let content;
    try {
        content = fs.readFileSync(inFile, 'utf8');
    } catch (e) {
        console.error("Failed to read file", e);
        return;
    }

    const lines = content.split(/\r?\n/);
    let currentFile = null;
    let currentContent = [];
    let count = 0;

    let i = 0;
    while (i < lines.length) {
        let line = lines[i];

        if (line.trim() === '================================================' &&
            i + 2 < lines.length &&
            lines[i+1].startsWith('FILE: ') &&
            lines[i+2].trim() === '================================================') {
            
            if (currentFile) {
                fs.mkdirSync(path.dirname(currentFile), { recursive: true });
                fs.writeFileSync(currentFile, currentContent.join('\n'), 'utf8');
                count++;
            }

            let filepath = lines[i+1].substring(6).trim();
            currentFile = path.join('d:\\fccc', filepath);
            currentContent = [];
            i += 3;

            if (i < lines.length && lines[i].trim() === '') {
                i++;
            }
            continue;
        }

        if (currentFile) {
            currentContent.push(line);
        }

        i++;
    }

    if (currentFile) {
        fs.mkdirSync(path.dirname(currentFile), { recursive: true });
        fs.writeFileSync(currentFile, currentContent.join('\n'), 'utf8');
        count++;
    }

    console.log(`Extraction complete. Extracted ${count} files.`);
}

extractProject();
