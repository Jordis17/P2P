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
RTL = sorted(p for p in DESIGN.glob("*.sv") if p.name != "uart_core.sv")

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


def lint() -> int:
    fallos = 0
    # top.sv solo tiene sentido revisarlo con todo junto: por si solo no
    # encuentra los modulos que instancia.
    for fuente in (p for p in RTL if p.name != "top.sv"):
        r = subprocess.run(["verilator", "--lint-only", "-Wall", str(fuente)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  LINT {fuente.name}\n{r.stderr}")
            fallos += 1
    # el top solo se puede revisar con todo junto
    r = subprocess.run(["verilator", "--lint-only", "-Wall", "--top-module", "top"]
                       + [str(p) for p in RTL]
                       + [str(AQUI / "uart_core_sim.sv"),
                          str(AQUI / "uart_core_model.sv")],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("  LINT del sistema completo\n" + r.stderr)
        fallos += 1
    print(f"  lint: {len(RTL)} archivos de RTL, {fallos} con avisos")
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
