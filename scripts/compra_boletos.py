from brownie import rifa, config, accounts, network
 
def main():
    account = accounts.add(config["wallets"]["from_key"])
    mirifa = rifa[-1]
    numboletos = 3
    value = mirifa.getPrecioBoletos(numboletos)
    compra_paula = mirifa.compraBoleto(numboletos, {'from': account, "value":value})
    print("Paula tiene ", mirifa.misBoletos({'from': account})," boletos")
    compra_paula.wait(1)
    print("bote: ", mirifa.bote())
