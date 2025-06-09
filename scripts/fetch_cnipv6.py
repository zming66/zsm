
import requests
import json

def fetch_ipv6_list():
    # 数据源1：APNIC最新分配记录
    apnic_url = "http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
    # 数据源2：备用CHN路由项目
    backup_url = "https://raw.githubusercontent.com/allenzha/chn-iplist/master/chnroute-ipv6.txt"
    
    try:
        r = requests.get(apnic_url)
        china_ips = [line for line in r.text.splitlines() 
                    if 'CN|ipv6' in line]
        with open('data/raw_ipv6.txt', 'w') as f:
            f.write('\n'.join(china_ips))
    except Exception as e:
        print(f"使用备用数据源，原因：{str(e)}")
        r = requests.get(backup_url)
        with open('data/raw_ipv6.txt', 'w') as f:
            f.write(r.text)

if __name__ == '__main__':
    fetch_ipv6_list()
