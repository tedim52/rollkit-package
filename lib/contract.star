
# can use script as a library or a script for executing contract queries on a localwasm network
def run(
    plan, 
    deploy_contract=False, 
    instantiate_contract=False): 
    # run whatever contract queries you'd like to run:

    # if deploy_contract:
    # rollup_node = plan.get_service(name="wasm-rollup")
    # deploy_optimized_nameservice_contract(plan, "http://{0}:{1}".format(rollup_node.ip_address, 36657), "wasmd-config")
    deploy_optimized_nameservice_contract(plan, "http://{0}:{1}".format("172.16.0.10", 36657), "wasmd-config")

    # if instantiate_contract:
        # instantiate_contract(plan)


# returns tx hash of nameservice contract deployed to localwasm network
def deploy_optimized_nameservice_contract(plan, node_endpoint, network_config):
    contract_deployment_cmd = [
        "wasmd tx wasm store /artifacts/cw_nameservice.wasm",
        "--from localwasm-key",
        "--keyring-backend test",
        "--chain-id localwasm",
        "--gas-prices 0.025uwasm",
        "--gas auto",
        "--gas-adjustment 1.3",
        "--node {0}".format(node_endpoint), 
        "--output json -y | jq -r '.txhash'",
    ]
    deploy_contract_result = plan.run_sh(
        image="tedim52/wasmd:latest",
        run=" ".join(contract_deployment_cmd),
        files={
            "/root/.wasmd/": network_config,
            "/artifacts/": get_optimized_nameservice_contract(plan),
        },
        description="Deploying nameservice contract to network"
    )
    tx_hash = deploy_contract_result.output
    return tx_hash

def get_optimized_nameservice_contract(plan):
    optimize_contract_result = plan.run_sh(
        run="cargo wasm && optimize.sh .",
        image="cosmwasm/rust-optimizer:0.12.6",
        files={
            "/code": get_nameservice_contract_code(plan),
        },
        store=[
            StoreSpec(src="/code/target/wasm32-unknown-unknown/release/cw_nameservice.wasm", name="nameservice-contract-bytecode"),
            StoreSpec(src="/code/artifacts/cw_nameservice.wasm", name="optimized-nameservice-contract-bytecode"),
        ],
        wait="25m",
        description="Building and optimizing nameservice contract (may take a while)",
    )
    return optimize_contract_result.files_artifacts[1] # files artifact for "optimized-nameservice-contract"

def get_nameservice_contract_code(plan):
    git_clone_result = plan.run_sh(
        image="alpine/git",
        run="git clone {0}".format("https://github.com/InterWasm/cw-contracts"),
        store=[
            StoreSpec(src="/git/cw-contracts/contracts/nameservice", name="nameservice-contract-code")
        ],
        description="Getting nameservice contract code"
    )
    return git_clone_result.files_artifacts[0] # files artifact for "nameservice-contract-code"

# TODO: Implement contract interaction functions
def get_code_id(plan):
    return

def instantiate_contract(plan):
    return

def register_name(plan):
    return