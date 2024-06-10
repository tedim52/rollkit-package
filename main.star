da_node = import_module("github.com/tedim52/celestia-da-node-package/main.star")
contract_utils = import_module("./lib/contract.star")

RPC_PORT_NUM = 36657
P2P_PORT_NUM = 36656

# TODO: this should be returned by the da_node package
DA_NODE_AUTH_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBbGxvdyI6WyJwdWJsaWMiLCJyZWFkIiwid3JpdGUiLCJhZG1pbiJdfQ.oA9eZRW5MowKp17AhxNTqYCAc37J_jcsu3rKh2F4Cb4"

def run(
    plan,
    da_image="ghcr.io/celestiaorg/celestia-node:v0.13.6",
    core_grpc_port="9090",
    core_ip="full.consensus.mocha-4.celestia-mocha.com",
    core_rpc_port="26657",
    gateway=False,
    gateway_addr="localhost",
    gateway_port="26659",
    headers_trusted_hash="8932B706216780C2660A9343A7F2B40A549BFA141D6B1CCA1E676306C35B25EA",
    headers_trusted_peers="",
    daser_sample_from=1264456,
    keyring_accname="",
    keyring_backend="test",
    log_level="INFO",
    log_level_module="",
    metrics= False,
    metrics_endpoint="localhost:4318",
    metrics_tls=True,
    node_config="",
    p2p_metrics=False,
    p2p_mutual="",
    p2p_network="mocha",
    pprof=False,
    enable_pyroscope=True,
    pyroscope_tracing=True,
    rpc_addr="0.0.0.0",
    rpc_port="26658",
    tracing=False,
    tracing_endpoint="localhost:4318",
    tracing_tls=True
    ):
    """
    Launches local CosmWasm roll up.

    Args:
        da_image (string):
        core_grpc_port (string):
        core_ip (string):
        core_rpc_port (string):
        gateway (bool):
        gateway_addr (string):
        gateway_port (string):
        headers_trusted_hash (string):
        headers_trusted_peers (string):
        daser_sample_from (int):
        keyring_accname (string):
        keyring_backend (string):
        log_level (string):
        log_level_module (string):
        metrics (bool):
        metrics_endpoint (string):
        metrics_tls (bool):
        node_config (string):
        p2p_metrics (bool):
        p2p_mutual (string):
        p2p_network (string):
        pprof (string):
        enable_pyroscope (bool):
        pyroscope_tracing (bool):
        rpc_addr (string):
        rpc_port (string):
        tracing (bool):
        tracing_endpoint (string):
        tracing_tls (bool):
    """
    # start local DA node
    # TODO: return auth token
    da_node_rpc_endpoint = da_node.run(
        plan,
        da_image,
        core_grpc_port,
        core_ip,
        core_rpc_port,
        gateway,
        gateway_addr,
        gateway_port,
        headers_trusted_hash,
        headers_trusted_peers,
        daser_sample_from,
        keyring_accname,
        keyring_backend,
        log_level,
        log_level_module,
        metrics,
        metrics_endpoint,
        metrics_tls,
        node_config,
        p2p_metrics,
        p2p_mutual,
        p2p_network,
        pprof,
        enable_pyroscope,
        pyroscope_tracing,
        rpc_addr,
        rpc_port,
        tracing,
        tracing_endpoint,
        tracing_tls,
    )
    plan.print("connecting to da layer via {0}".format(da_node_rpc_endpoint))
 
    # configure init script to point to da node, and other provided values
    init_script_tmpl = read_file(src="./static-files/init.sh.tmpl")
    init_script_artifact = plan.render_templates(
        name="wasmd-init-script", 
        config={
            "init.sh": struct(
                template=init_script_tmpl,
                data={
                    # if we need to parameterize anything in the init script can do this object
                },
            )
        },
    )

    # run init script and save  config
    result = plan.run_sh(
        image="tedim52/wasmd:latest", # contains wasmd with rollkit swapped in place of cometbft
        run="chmod u+x /root/init.sh && /bin/sh -c /root/init.sh",
        files={
            "/root/": init_script_artifact,
        },
        store=[
            StoreSpec(src="/root/.wasmd/*", name="wasmd-config")
        ]
    )
    wasm_rollup_config = result.files_artifacts[0]

    # start rollup node
    wasmd_start_cmd = [
        "wasmd",
        "start",
        "--rollkit.aggregator",
        "--rollkit.da_address {0}".format(da_node_rpc_endpoint),
        "--rollkit.da_auth_token {0}".format(DA_NODE_AUTH_TOKEN),
        "--rpc.laddr tcp://0.0.0.0:{0}".format(RPC_PORT_NUM), # TODO: parameterize ports
        "--grpc.address 0.0.0.0:9290", 
        "--p2p.laddr \"0.0.0.0:{0}\"".format(P2P_PORT_NUM),
        "--minimum-gas-prices=\"0.025uwasm\"",
    ]
    rollup_node = plan.add_service(
        name="wasm-rollup",
        config=ServiceConfig(
            image="tedim52/wasmd:latest",
            files={
                "/root/.wasmd/": wasm_rollup_config # mount the config output from init script to the service
            },
            cmd=["/bin/sh", "-c", " ".join(wasmd_start_cmd)],
            ports={
                # TODO: figure out why rpc and grpc ports arent being picked up
                "rpc": PortSpec(
                    number=RPC_PORT_NUM,
                    transport_protocol="TCP",
                    application_protocol="http",
                ),
                "grpc": PortSpec(
                    number=9290,
                    transport_protocol="TCP",
                    application_protocol="http",
                ),
                "p2p": PortSpec(
                    number=36656,
                    transport_protocol="TCP",
                    application_protocol="http",
                ),
            },
            ready_conditions=ReadyCondition(
                recipe=ExecRecipe(
                    command=["wasmd", "status", "-n", "tcp://127.0.0.1:{0}".format(RPC_PORT_NUM)], 
                    extract = {
                        "output": "fromjson | .node_info.network",
                    }
                ),
                field="extract.output", 
                assertion="==",
                target_value="localwasm", 
                interval="1s",
                timeout="10s",
            )
        )
    )
    rollup_node_rpc_endpoint = "http://{0}:{1}".format(rollup_node.ip_address, rollup_node.ports["rpc"].number)
    plan.print("Roll up node rpc endpoint: {0}".format(rollup_node_rpc_endpoint))
   
    contract_deployment_tx_hash = contract_utils.deploy_optimized_nameservice_contract(plan, rollup_node_rpc_endpoint, wasm_rollup_config)
    plan.print("Tx hash of nameservice contract deployment: {0}".format(contract_deployment_tx_hash))