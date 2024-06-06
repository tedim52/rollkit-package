da_node = import_module("github.com/tedim52/celestia-da-node-package/main.star")

def run(plan, args):
    # start local DA node
    da_node_rpc_endpoint = da_node.run(plan, args)

