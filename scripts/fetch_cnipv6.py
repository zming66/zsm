
import requests
import os

def fetch_ipv6_list():
    # 确保data目录存在
    os.makedirs('data', exist_ok=True)
    
    apnic_url = "http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
    backup_url = "https://raw.githubusercontent.com/allenzha/chn-iplist/master/chnroute-ipv6.txt"
    
    try:
        r = requests.get(apnic_url, timeout=10)
        china_ips = [line for line in r.text.splitlines() 
                    if 'CN|ipv6' in line]
        with open('data/raw_ipv6.txt', 'w') as f:
            f.write('\n'.join(china_ips))
    except Exception as e:
        print(f"使用备用数据源，原因：{str(e)}")
        r = requests.get(backup_url, timeout=10)
        with open('data/raw_ipv6.txt', 'w') as f:
            f.write(r.text)

if __name__ == '__main__':
    fetch_ipv6_list()
