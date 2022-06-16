from brownie import rifa, config, accounts, network

def leer_contrato():
    mirifa = rifa[-1]
    print("Numero ronda ", mirifa.getRondaId())
    print("Bote: ", mirifa.bote())
    print("Precio un boleto en eth: ", mirifa.getPrecioBoletoEth())
    print("Dirección contrato: ", mirifa.getDir_contrato())
    print("Ultimo ganador: ", mirifa.getUltimoGanador())


def main():
    leer_contrato()