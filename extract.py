import os

def extract_project():
    in_file = r'd:\fccc\apppp'
    
    try:
        with open(in_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except UnicodeDecodeError:
        with open(in_file, 'r', encoding='latin-1') as f:
            lines = f.readlines()
        
    current_file = None
    current_content = []
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        if line.strip() == "================================================" and \
           i + 2 < len(lines) and \
           lines[i+1].startswith("FILE: ") and \
           lines[i+2].strip() == "================================================":
           
           if current_file:
               os.makedirs(os.path.dirname(current_file), exist_ok=True)
               with open(current_file, 'w', encoding='utf-8') as out_f:
                   out_f.writelines(current_content)
                   
           filepath = lines[i+1][6:].strip()
           filepath = filepath.replace('/', os.sep)
           current_file = os.path.join(r'd:\fccc', filepath)
           current_content = []
           i += 3
           
           if i < len(lines) and lines[i].strip() == "":
               i += 1
               
           continue
           
        if current_file:
            current_content.append(line)
            
        i += 1

    if current_file:
        os.makedirs(os.path.dirname(current_file), exist_ok=True)
        with open(current_file, 'w', encoding='utf-8') as out_f:
            out_f.writelines(current_content)
            
    print("Extraction complete.")

if __name__ == '__main__':
    extract_project()
