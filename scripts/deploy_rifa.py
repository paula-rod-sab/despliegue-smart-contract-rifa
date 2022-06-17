from brownie import config, network, rifa, accounts

def deploy_rifa():
    account = accounts.add(config["wallets"]["from_key"])
    rifa.deploy(
        config["networks"][network.show_active()]["boletoEnEur"],
        config["networks"][network.show_active()]["intervaloSeg"],
        config["networks"][network.show_active()]["dirAsociacion"],
        config["networks"][network.show_active()]["Agg_eth_usd"],
        config["networks"][network.show_active()]["Agg_eur_usd"],
        config["networks"][network.show_active()]["vrfCoordinador"],
        config["networks"][network.show_active()]["keyHash"],
        config["networks"][network.show_active()]["subId"],
        config["networks"][network.show_active()]["callbackGas"],
        {"from":account, "priority_fee": 35000000000})
    print(f"Contrato desplegado")
def main():
    deploy_rifa()
    