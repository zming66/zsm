import os
from datetime import datetime

def convert_format():
    os.makedirs('outputs', exist_ok=True)
    
    with open('data/raw_ipv6.txt') as f:
        lines = f.read().splitlines()
    
    ros_rules = [
        "# 中国IPv6地址列表 - 自动生成",
        f"# 更新时间: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "/ipv6 firewall address-list remove [/ipv6 firewall address-list find list=CN]",
        "/ipv6 firewall address-list"
    ]
    
    for line in lines:
        if '::' in line or '|' in line:
            cidr = line.split('|')[-1] if '|' in line else line.strip()
            ros_rules.append(f'add address={cidr} list=CN')
    
    with open('outputs/cn_ipv6.rsc', 'w') as f:
        f.write('\n'.join(ros_rules))

if __name__ == '__main__':
    convert_format()
