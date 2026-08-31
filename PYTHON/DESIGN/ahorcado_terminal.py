#!/usr/bin/env python3
"""
ahorcado_terminal.py - Terminal del jugador

La FPGA lleva el juego entero. Esta aplicacion solo hace dos cosas:
mandar la letra que el jugador escribe y mostrar lo que la FPGA
responde. No guarda la palabra secreta, no elige palabra, no decide
quien gana y no lleva el tiempo. Si alguna vez parece que esta terminal
"sabe" algo del juego, es porque la FPGA se lo acaba de decir.

Protocolo
---------
De la PC a la FPGA va un solo byte, de la A a la Z.

De la FPGA a la PC vienen lineas ASCII terminadas en salto de linea, con
campos de ancho fijo:

    START:<M>:<LL>    M es F o D, LL es la longitud con dos digitos
    PATT:<p>          patron, con guion bajo en lo oculto
    LET:<X>:<R>       letra y resultado: 'OK ', 'NO ' o 'RPT'
    ERR:<n>           intentos fallidos que quedan
    END:<E>:<W>       desenlace WIN, LER o LTO, y la palabra completa

Los campos son de ancho fijo justamente para que aqui se puedan trocear
por posicion, sin expresiones regulares. Una linea que no encaje se
reporta y se descarta: nunca detiene la aplicacion.

Por que hay un hilo lector
--------------------------
El limite de tiempo corre en la FPGA. Si el jugador se queda pensando,
la partida puede terminar mientras la terminal esta esperando que
escriba algo. Con lectura sincronica ese aviso no se veria hasta que
escribiera, que es justo cuando ya no sirve. El hilo lector recibe
siempre, avisa en pantalla si la partida termina durante la espera, y la
letra que el jugador escriba despues se descarta.

Uso
---
    pip install pyserial
    python ahorcado_terminal.py --port COM4           (Windows)
    python ahorcado_terminal.py --port /dev/ttyUSB0   (Linux)
    python ahorcado_terminal.py --list                lista los puertos
"""

import argparse
import queue
import sys
import threading

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("Falta pyserial. Instalalo con:  pip install pyserial")


BAUDIOS = 115200

RESULTADOS = {
    "OK ": "correcta",
    "NO ": "incorrecta",
    "RPT": "repetida, no cuenta",
}

DESENLACES = {
    "WIN": "GANASTE",
    "LER": "PERDISTE: se acabaron los intentos",
    "LTO": "PERDISTE: se acabo el tiempo",
}

MODOS = {"F": "Facil", "D": "Dificil"}


# ---------------------------------------------------------------------
# Analisis de las lineas recibidas
# ---------------------------------------------------------------------
def parsear(linea):
    """Devuelve (tipo, datos) o None si la linea no encaja con nada.

    El troceo es por posicion porque los campos son de ancho fijo. Cada
    caso comprueba su propio largo antes de cortar, de modo que una
    linea a medias o con ruido no rompe nada.
    """
    if linea.startswith("START:"):
        if len(linea) == 10 and linea[7] == ":":
            modo = linea[6]
            largo = linea[8:10]
            if modo in MODOS and largo.isdigit():
                return "inicio", {"modo": modo, "longitud": int(largo)}

    elif linea.startswith("PATT:"):
        patron = linea[5:]
        if patron:
            return "patron", {"patron": patron}

    elif linea.startswith("LET:"):
        if len(linea) == 9 and linea[5] == ":":
            letra = linea[4]
            resultado = linea[6:9]
            if resultado in RESULTADOS:
                return "letra", {"letra": letra, "resultado": resultado}

    elif linea.startswith("ERR:"):
        if len(linea) == 5 and linea[4].isdigit():
            return "intentos", {"intentos": int(linea[4])}

    elif linea.startswith("END:"):
        if len(linea) > 8 and linea[7] == ":":
            desenlace = linea[4:7]
            palabra = linea[8:]
            if desenlace in DESENLACES:
                return "fin", {"desenlace": desenlace, "palabra": palabra}

    return None


# ---------------------------------------------------------------------
# Hilo lector
# ---------------------------------------------------------------------
def lector(puerto, cola, esperando_letra):
    """Arma lineas con lo que llega y las mete en la cola.

    Si la partida termina mientras el jugador esta escribiendo, lo avisa
    en pantalla; si no, el aviso no aparece hasta que escriba, que es
    cuando ya no sirve de nada.
    """
    buffer = bytearray()
    while True:
        try:
            datos = puerto.read(puerto.in_waiting or 1)
        except Exception as error:                    # el puerto se fue
            cola.put(("desconectado", {"detalle": str(error)}))
            return

        for byte in datos:
            if byte == 0x0A:                          # salto de linea
                linea = buffer.decode("ascii", errors="replace")
                buffer.clear()
                if linea.startswith("END:") and esperando_letra.is_set():
                    print("\n  >> la FPGA termino la partida. "
                          "Pulsa Enter para ver el resultado.")
                cola.put(("linea", {"texto": linea}))
            elif byte != 0x0D:                        # retorno de carro
                buffer.append(byte)
                if len(buffer) > 80:                  # linea absurda: al tacho
                    buffer.clear()


# ---------------------------------------------------------------------
# Estado que se muestra, tal como lo va diciendo la FPGA
# ---------------------------------------------------------------------
class Estado:
    def __init__(self):
        self.reiniciar()

    def reiniciar(self):
        self.modo = None
        self.longitud = None
        self.patron = None
        self.intentos = None
        self.ultima = None

    def mostrar(self):
        if self.patron is not None:
            print("  Palabra : " + " ".join(self.patron))
        if self.intentos is not None:
            print(f"  Intentos: {self.intentos}")
        if self.ultima is not None:
            letra, resultado = self.ultima
            print(f"  Ultima  : {letra} -> {RESULTADOS[resultado]}")


# ---------------------------------------------------------------------
# Entrada del jugador
# ---------------------------------------------------------------------
def pedir_letra(esperando_letra):
    """Devuelve una letra A-Z, o None si el jugador quiere salir.

    Vuelve a preguntar cuantas veces haga falta. Nada de lo que escriba
    el jugador llega al puerto sin pasar por aqui.
    """
    while True:
        esperando_letra.set()
        try:
            texto = input("  Letra: ")
        except (EOFError, KeyboardInterrupt):
            print()
            return None
        finally:
            esperando_letra.clear()

        texto = texto.strip()

        # Solo "salir" cierra. Nada de atajos de una letra: la Q es una
        # letra del banco y el jugador tiene que poder intentarla.
        if texto.lower() == "salir":
            return None
        if len(texto) == 0:
            print("  Escribe una letra.")
            continue
        if len(texto) > 1:
            print("  Solo una letra por turno.")
            continue

        letra = texto.upper()
        if not letra.isalpha():
            print("  Eso no es una letra.")
            continue
        if not ("A" <= letra <= "Z"):
            # El banco de palabras no lleva tildes ni la enye, asi que la
            # FPGA solo entiende A-Z y descartaria el byte en silencio.
            print("  El banco de palabras no usa tildes ni la enye.")
            continue

        return letra


# ---------------------------------------------------------------------
def jugar(puerto, cola, esperando_letra):
    estado = Estado()
    en_partida = False
    turno = False        # la FPGA ya dijo todo lo de la jugada anterior

    print("Conectado. Elegi el modo en la tarjeta y pulsa el boton derecho")
    print("para empezar. Escribi 'salir' para cerrar.\n")

    while True:
        # ---- atender lo que haya dicho la FPGA ----
        while not turno or not cola.empty():
            tipo, datos = cola.get()

            if tipo == "desconectado":
                print(f"\nSe perdio el puerto serie: {datos['detalle']}")
                return

            evento = parsear(datos["texto"])
            if evento is None:
                if datos["texto"]:
                    print(f"  (linea no reconocida: {datos['texto']!r})")
                continue

            clase, campos = evento

            if clase == "inicio":
                estado.reiniciar()
                estado.modo = campos["modo"]
                estado.longitud = campos["longitud"]
                en_partida = True
                turno = False
                print(f"\n--- Partida nueva | modo {MODOS[campos['modo']]} "
                      f"| {campos['longitud']} letras ---")

            elif clase == "patron":
                estado.patron = campos["patron"]

            elif clase == "letra":
                estado.ultima = (campos["letra"], campos["resultado"])
                if campos["resultado"] == "RPT":
                    # La repetida no trae patron ni intentos detras: con
                    # esa linea se cierra la jugada.
                    print()
                    estado.mostrar()
                    turno = en_partida

            elif clase == "intentos":
                estado.intentos = campos["intentos"]
                print()
                estado.mostrar()
                turno = en_partida

            elif clase == "fin":
                print()
                print(f"  {DESENLACES[campos['desenlace']]}")
                print(f"  La palabra era: {campos['palabra']}")
                print("\nElegi el modo en la tarjeta y pulsa el boton derecho")
                print("para jugar otra vez.\n")
                estado.reiniciar()
                en_partida = False
                turno = False

        # ---- turno del jugador ----
        letra = pedir_letra(esperando_letra)
        if letra is None:
            print("Hasta luego.")
            return

        # Mientras se escribia pudo llegar el final de la partida. En ese
        # caso la letra ya no vale para nada.
        if not cola.empty() or not en_partida:
            turno = False
            continue

        try:
            puerto.write(letra.encode("ascii"))
        except Exception as error:
            print(f"\nNo se pudo enviar: {error}")
            return
        turno = False


# ---------------------------------------------------------------------
def main():
    analizador = argparse.ArgumentParser(
        description="Terminal del jugador para el Ahorcado en FPGA")
    analizador.add_argument("--port", help="puerto serie, por ejemplo COM4")
    analizador.add_argument("--baud", type=int, default=BAUDIOS,
                            help=f"baudios (por omision {BAUDIOS})")
    analizador.add_argument("--list", action="store_true",
                            help="lista los puertos disponibles y termina")
    opciones = analizador.parse_args()

    puertos = list(list_ports.comports())

    if opciones.list:
        if not puertos:
            print("No hay puertos serie disponibles.")
        for p in puertos:
            print(f"{p.device}  {p.description}")
        return 0

    nombre = opciones.port
    if nombre is None:
        if len(puertos) == 1:
            nombre = puertos[0].device
            print(f"Unico puerto disponible: {nombre}")
        else:
            print("Indica el puerto con --port. Para verlos: --list")
            return 1

    try:
        # El tiempo de espera evita que el hilo lector se quede clavado
        # cuando la tarjeta no dice nada.
        puerto = serial.Serial(nombre, opciones.baud, timeout=0.2)
    except Exception as error:
        print(f"No se pudo abrir {nombre}: {error}")
        return 1

    cola = queue.Queue()
    esperando_letra = threading.Event()

    hilo = threading.Thread(target=lector,
                            args=(puerto, cola, esperando_letra),
                            daemon=True)
    hilo.start()

    try:
        jugar(puerto, cola, esperando_letra)
    except KeyboardInterrupt:
        print("\nInterrumpido.")
    finally:
        puerto.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
