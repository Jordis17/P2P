#!/usr/bin/env python3
"""
run_tests.py - Corre toda la regresion de testbenches con iverilog

Un solo comando para los dieciseis testbenches, con el resumen de cada
uno y un total al final.

    python run_tests.py            corre todo
    python run_tests.py lcd        corre solo los que digan lcd
    python run_tests.py --lint     ademas revisa el RTL con verilator

Por que hace falta un script y no un comodin
--------------------------------------------
El nucleo UART real esta en VHDL e iverilog no lo compila. DESIGN y
SIMULATION declaran los dos un modulo uart_core: el de DESIGN instancia
las entidades VHDL y es el que usa Vivado, y el de SIMULATION resuelve lo
mismo con el modelo de comportamiento. Compilar DESIGN/*.sv de un tiron
mezclaria los dos. Aqui la lista se arma excluyendo el que no toca.

Hace falta iverilog en el PATH. En Windows se instala con MSYS2 o se usa
la simulacion de Vivado, que si entiende VHDL y es la que sirve para el
contraste contra el nucleo real.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

AQUI   = Path(__file__).resolve().parent
DESIGN = AQUI.parent / "DESIGN"

# El nucleo de DESIGN instancia VHDL: iverilog usa el de aqui.
#
# Los paquetes van primero. iverilog compila en el orden de la linea de
# comandos y necesita el paquete antes que cualquier modulo que lo
# importe; por orden alfabetico, lcd_screen_ctrl.sv caeria antes de
# lcd_screen_pkg.sv y la compilacion fallaria. Vivado resuelve esa
# dependencia por su cuenta, iverilog no.
_FUENTES = sorted(p for p in DESIGN.glob("*.sv") if p.name != "uart_core.sv")
RTL = ([p for p in _FUENTES if p.stem.endswith("_pkg")] +
       [p for p in _FUENTES if not p.stem.endswith("_pkg")])

# Archivos de apoyo que necesita cada testbench, ademas de todo el RTL.
APOYO = {
    "uart_peripheral": ["uart_core_model.sv"],
    "uart_test_block": ["uart_core_model.sv"],
    "uart_msg":        ["uart_core_model.sv"],
    "top":             ["uart_core_model.sv", "uart_core_sim.sv"],
}


def correr(tb: Path) -> tuple[str, str]:
    nombre = tb.stem[3:]                       # quita el prefijo tb_
    fuentes = [str(tb)] + [str(p) for p in RTL]
    fuentes += [str(AQUI / n) for n in APOYO.get(nombre, [])]

    with tempfile.TemporaryDirectory() as tmp:
        binario = str(Path(tmp) / "tb")
        compilacion = subprocess.run(
            ["iverilog", "-g2012", "-s", tb.stem, "-o", binario] + fuentes,
            capture_output=True, text=True)
        if compilacion.returncode != 0:
            return nombre, "ERROR DE COMPILACION\n" + compilacion.stderr.strip()

        ejecucion = subprocess.run([binario], capture_output=True, text=True,
                                   timeout=600)

    for linea in ejecucion.stdout.splitlines():
        if linea.strip().startswith(("PASS", "FAIL")):
            return nombre, linea.strip()
    return nombre, "SIN RESUMEN\n" + ejecucion.stdout.strip()


# Archivos que solo tienen sentido revisar con todo junto, porque
# instancian otros modulos y por si solos no los encuentran.
SOLO_CON_TODO = {"top.sv", "lcd_screen_ctrl.sv"}


def lint() -> int:
    fallos = 0

    # Los paquetes acompanan a cada archivo del repaso individual: quien
    # los importa no compila sin ellos. Por si solos no se revisan, porque
    # un paquete no es un modulo de nivel superior.
    paquetes = [str(p) for p in RTL if p.stem.endswith("_pkg")]

    # Al revisar un modulo suelto con el paquete al lado, verilator avisa
    # de las constantes del paquete que ese modulo no usa. En el diseno
    # completo todas se usan, asi que en el repaso individual ese aviso no
    # dice nada y se calla. El repaso del sistema completo, que es el que
    # vale, se hace mas abajo sin silenciar nada.
    sueltos = [p for p in RTL
               if p.name not in SOLO_CON_TODO and not p.stem.endswith("_pkg")]
    for fuente in sueltos:
        r = subprocess.run(["verilator", "--lint-only", "-Wall",
                            "-Wno-UNUSEDPARAM"] + paquetes + [str(fuente)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  LINT {fuente.name}\n{r.stderr}")
            fallos += 1

    # El sistema completo, sin excepciones de ningun tipo.
    r = subprocess.run(["verilator", "--lint-only", "-Wall", "--top-module", "top"]
                       + [str(p) for p in RTL]
                       + [str(AQUI / "uart_core_sim.sv"),
                          str(AQUI / "uart_core_model.sv")],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("  LINT del sistema completo\n" + r.stderr)
        fallos += 1

    print(f"  lint: {len(sueltos)} modulos por separado y el sistema completo, "
          f"{fallos} con avisos")
    print(f"  ({len(paquetes)} paquete(s) de apoyo; "
          f"{', '.join(sorted(SOLO_CON_TODO))} solo con todo junto)")
    print("  (uart_core.sv no se revisa aqui: instancia entidades VHDL)")
    return fallos


def main() -> int:
    filtro = [a for a in sys.argv[1:] if not a.startswith("-")]
    tbs = sorted(AQUI.glob("tb_*.sv"))
    if filtro:
        tbs = [t for t in tbs if any(f in t.stem for f in filtro)]
    if not tbs:
        print("No hay testbenches que encajen con eso.")
        return 1

    fallos = 0
    if "--lint" in sys.argv[1:]:
        print()
        fallos += lint()

    print()
    for tb in tbs:
        nombre, resumen = correr(tb)
        print(f"  {nombre:<20} {resumen}")
        if not resumen.startswith("PASS"):
            fallos += 1

    print()
    if fallos == 0:
        print(f"  TODO BIEN  {len(tbs)} testbenches, ninguna comprobacion fallida")
    else:
        print(f"  HAY FALLOS  {fallos} de {len(tbs)}")
    print()
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
