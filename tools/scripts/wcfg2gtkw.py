import xml.etree.ElementTree as ET
import os
import sys

def convert_wcfg_to_gtkw(wcfg_file, gtkw_file):
    try:
        tree = ET.parse(wcfg_file)
        root = tree.getroot()
    except Exception as e:
        print(f"Error parsing {wcfg_file}: {e}")
        return

    with open(gtkw_file, 'w', encoding='utf-8') as f:
        # Header
        f.write("[*]\n")
        f.write("[*] GTKWave Analyzer\n")
        f.write("[*]\n")
        f.write('[dumpfile] "tb_soc_top.vcd"\n')
        f.write('[timestart] 0\n')
        
        def process_wvobject(node):
            obj_type = node.get('type')
            if obj_type == 'group':
                label = ""
                for prop in node.findall('obj_property'):
                    if prop.get('name') == 'label':
                        label = prop.text
                        break
                    elif prop.get('name') == 'DisplayName' and not label:
                        label = prop.text # fallback
                
                if not label:
                    label = "Group"
                
                # Start group
                f.write(f"@c00200\n-{label}\n")
                
                for child in node.findall('wvobject'):
                    process_wvobject(child)
                
                # End group
                f.write(f"@1401200\n-{label}\n")
                
            elif obj_type in ['logic', 'array', 'vbus']:
                fp_name = node.get('fp_name')
                if fp_name:
                    # Convert Vivado path /tb_soc_top/clk to GTKWave path tb_soc_top.clk
                    sig_name = fp_name.lstrip('/').replace('/', '.')
                    
                    # Check if ElementShortName contains brackets (for array ranges)
                    short_name_node = node.find("obj_property[@name='ElementShortName']")
                    if short_name_node is not None and short_name_node.text and '[' in short_name_node.text:
                        brackets = short_name_node.text[short_name_node.text.find('['):]
                        sig_name += brackets
                    
                    # Try to get Radix
                    radix_node = node.find("obj_property[@name='Radix']")
                    radix = radix_node.text if radix_node is not None else ""
                    
                    if radix == 'HEXRADIX':
                        f.write("@22\n") # Hex
                    elif radix == 'UNSIGNEDDECRADIX':
                        f.write("@24\n") # Unsigned dec
                    elif radix == 'SIGNEDDECRADIX':
                        f.write("@25\n") # Signed dec
                    elif radix == 'BINARYRADIX':
                        f.write("@28\n") # Binary
                    else:
                        # Default based on type
                        if obj_type == 'logic':
                            f.write("@28\n") # Binary
                        else:
                            f.write("@22\n") # Hex for arrays
                            
                    f.write(sig_name + "\n")

        for node in root.findall('wvobject'):
            process_wvobject(node)
            
    print(f"Successfully converted {wcfg_file} to {gtkw_file}")

if __name__ == '__main__':
    wcfg_path = r'd:\Academic\myProjects\my-RISCV-Projs\sim\tb_soc_top_behav.wcfg'
    gtkw_path = r'd:\Academic\myProjects\my-RISCV-Projs\sim\top_core_behv_fromvivado_test2.gtkw'
    convert_wcfg_to_gtkw(wcfg_path, gtkw_path)
