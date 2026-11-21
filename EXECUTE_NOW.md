# EXECUTE NOW: Close All TBDs

## Prerequisites (run once)
1. Install Vivado ML Standard (free WebPACK for Artix-7):
   - Download: https://www.xilinx.com/products/design-tools/vivado.html
   - Select "Vivado ML Standard Edition" -> "WebPACK" (free, no license needed for Artix-7)
   - Install on Mac/Windows/Linux (~20-30GB, requires GUI)

## EXECUTE THESE COMMANDS (copy-paste into Vivado Tcl Console)

### 1. OPEN ROUTED DESIGN
```tcl
# Option A: Open routed checkpoint (.dcp)
open_checkpoint /path/to/routed_design.dcp

# OR Option B: Open project and open implemented design
open_project /path/to/project.xpr
open_run impl_1
current_design [get_designs -filter {IS_ROUTE=1}]
```

### 2. RUN ALL REPORTS (copy-paste into Vivado Tcl Console)
```tcl
# 1. LUT/BRAM Utilization - MEASURED (FREE)
report_utilization
report_ram_utilization -include_lutram

# 2. Power Estimate - ESTIMATED
report_power

# 3. Save reports to files
write_file -force utilization_report.txt [report_utilization]
write_file -force power_report.txt [report_power]
```

### 3. PARSE + UPDATE DASHBOARD (run after reports generate)
```bash
cd /Users/playra/t27-lamb-labs
python3 << 'PYEOF'
import re, json, os

# Parse utilization_report.txt
with open('utilization_report.txt', 'r') as f:
    content = f.read()

patterns = {
    'luts_used': r'Slice LUTs\*?\s+(\d+)',
    'luts_total': r'Slice LUTs\*?\s+\d+\s+(\d+)',
    'luts_pct': r'Slice LUTs\*?\s+\d+\s+\d+\s+([\d.]+)%',
    'ffs_used': r'Slice FFs\s+(\d+)',
    'ffs_total': r'Slice FFs\s+\d+\s+(\d+)',
    'bram36_used': r'Block RAM Tile\s+(\d+)',
    'bram36_total': r'Block RAM Tile\s+\d+\s+(\d+)',
    'bram_pct': r'Block RAM Tile\s+\d+\s+\d+\s+([\d.]+)%',
    'dsp_used': r'DSPs\s+(\d+)',
    'dsp_pct': r'DSPs\s+\d+\s+\d+\s+([\d.]+)%',
}

data = {}
with open('utilization_report.txt', 'r') as f:
    content = f.read()

for key, pattern in {
        'luts_used': r'Slice LUTs\*?\s+(\d+)',
        'luts_total': r'Slice LUTs\*?\s+\d+\s+(\d+)',
        'luts_pct': r'Slice LUTs\*?\s+\d+\s+\d+\s+([\d.]+)%',
        'ffs_used': r'Slice FFs\s+(\d+)',
        'ffs_total': r'Slice FFs\s+\d+\s+(\d+)',
        'bram36_used': r'Block RAM Tile\s+(\d+)',
        'bram36_total': r'Block RAM Tile\s+\d+\s+(\d+)',
        'bram_pct': r'Block RAM Tile\s+\d+\s+\d+\s+([\d.]+)%',
        'dsp_used': r'DSPs\s+(\d+)',
        'dsp_pct': r'DSPs\s+\d+\s+\d+\s+([\d.]+)%',
    }.items():
    m = re.search(pattern, content)
    if m: data[key] = m.group(1)

# Parse power_report.txt
with open('power_report.txt', 'r') as f:
    content = f.read()

power_data = {}
m = re.search(r'Total On-Chip Power\s*:\s*([\d.]+)\s*W', content)
if m: power_w = float(m.group(1))

m = re.search(r'Confidence Level\s*:\s*(\w+)', content)
confidence = m.group(1) if m else 'Preliminary'

m = re.search(r'Total On-Chip Power.*?\(([^)]+)\)', content)
accuracy = m.group(1) if m else 'Preliminary'

print("=== EXTRACTED DATA ===")
print(f"LUTs: {data.get('luts_used', '?')}/{data.get('luts_total', '?')} ({data.get('luts_pct', '?')}%)")
print(f"FFs: {data.get('ffs_used', '?')}/{data.get('ffs_total', '?')} ({data.get('ffs_pct', '?')}%)")
print(f"BRAM36: {data.get('bram36_used', '?')}/{data.get('bram36_total', '?')} ({data.get('bram_pct', '?')}%)")
print(f"DSP: {data.get('dsp_used', '?')} ({data.get('dsp_pct', '?')}%)")
print(f"Power: {power_w}W ({confidence}, {accuracy})")
print(f"J/token: {float(power_w)/5.7:.3f} J/token (ESTIMATED)")
print(f"Confidence: {confidence} (±20% for Preliminary)")

# Save extracted data
with open('extracted_data.json', 'w') as f:
    json.dump({
        'luts_used': data.get('luts_used'),
        'luts_total': data.get('luts_total'),
        'luts_pct': data.get('luts_pct'),
        'ffs_used': data.get('ffs_used'),
        'ffs_total': data.get('ffs_total'),
        'ffs_pct': data.get('ffs_pct'),
        'bram36_used': data.get('bram36_used'),
        'bram36_total': data.get('bram36_total'),
        'bram_pct': data.get('bram_pct'),
        'dsp_used': data.get('dsp_used'),
        'dsp_pct': data.get('dsp_pct'),
        'power_w': power_w if 'power_w' in locals() else None,
        'confidence': confidence,
        'accuracy': accuracy
    }, f, indent=2)

print("\n=== COPY-PASTE TO UPDATE DASHBOARD ===")
print(f"LUTs: {data.get('luts_used', '?')}/{data.get('luts_total', '?')} ({data.get('luts_pct', '?')}%)")
print(f"FFs: {data.get('ffs_used', '?')}/{data.get('ffs_total', '?')} ({data.get('ffs_pct', '?')}%)")
print(f"BRAM36: {data.get('bram36_used', '?')}/{data.get('bram36_total', '?')} ({data.get('bram_pct', '?')}%)")
print(f"DSP: {data.get('dsp_used', '?')} ({data.get('dsp_pct', '?')}%)")
print(f"Power: {power_w}W ({confidence}, {accuracy})")
print(f"J/token: {float(power_w)/5.7:.3f} J/token (ESTIMATED)")
print(f"Confidence: {confidence} (±20% for Preliminary)")
PYEOF

chmod +x /Users/playra/t27-lamb-labs/extract_vivado_data.py
