def format_etcd_peer(pair, port):
    ip, name = pair
    return f"{name}=http://{ip}:{port}"

class FilterModule(object):
    def filters(self):
        return {
            'format_etcd_peer': format_etcd_peer
        }
