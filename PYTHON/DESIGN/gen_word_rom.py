#!/usr/bin/env python3
"""
Generador del banco de palabras -> FPGA/DESIGN/word_rom.sv

Fuente unica de verdad del banco. El orden de esta lista NO es
cosmetico: es lo que hace posible la seleccion directa del indice.

    indices  0..31 -> longitud >= 6  (validas para DIFICIL y para FACIL)
    indices 32..63 -> longitud 4 o 5 (validas solo para FACIL)

Gracias a ese orden, la seleccion de palabra es un truncamiento directo
del LFSR, sin modulo, sin rechazo y sin bucles:

    DIFICIL: rom_index = lfsr[4:0]   -> 0..31
    FACIL:   rom_index = lfsr[5:0]   -> 0..63

Uso:
    python gen_word_rom.py            # valida y genera ../rtl/word_rom.sv
    python gen_word_rom.py --check    # solo valida, no escribe
"""

import argparse
import sys
from pathlib import Path

MAX_LEN = 12
N_WORDS = 64
N_HARD = 32
HARD_MIN_LEN = 6

# --- Indices 0..31 : longitud >= 6 -----------------------------------------
HARD_WORDS = [
    "PUERTA", "SENSOR", "VOLCAN", "MADERA", "CAMISA",
    "BOTELLA", "VENTANA", "TECLADO", "MONITOR", "MEMORIA",
    "SISTEMA", "DIGITAL", "LAMPARA", "ESCUELA", "PLANETA",
    "CIRCUITO", "REGISTRO", "CONTADOR", "GUITARRA", "ELEFANTE",
    "MARIPOSA", "TELEFONO", "PANTALLA", "CUADERNO",
    "BICICLETA", "INGENIERO", "MICROFONO",
    "VENTILADOR",
    "COMPUTADORA", "LABORATORIO", "HERRAMIENTA", "RESISTENCIA",
]

# --- Indices 32..63 : longitud 4 o 5 ---------------------------------------
EASY_WORDS = [
    "CASA", "MESA", "SILLA", "LIBRO", "PERRO", "GATO", "LUNA", "NUBE",
    "FLOR", "ARBOL", "CIELO", "FUEGO", "AGUA", "VERDE", "ROJO", "AZUL",
    "NEGRO", "CINCO", "TRES", "SIETE", "OCHO", "NUEVE", "LAPIZ", "PAPEL",
    "CABLE", "DATOS", "RELOJ", "CHIP", "PUNTO", "CAMPO", "PLAYA", "BARCO",
]

WORDS = HARD_WORDS + EASY_WORDS


def validate(words):
    """Devuelve una lista de errores. Vacia = banco valido."""
    errs = []

    if len(words) != N_WORDS:
        errs.append(f"se esperaban {N_WORDS} palabras, hay {len(words)}")

    dupes = {w for w in words if words.count(w) > 1}
    if dupes:
        errs.append(f"palabras repetidas: {sorted(dupes)}")

    for i, w in enumerate(words):
        if not w.isascii() or not w.isalpha() or not w.isupper():
            errs.append(f"[{i}] '{w}': solo se permiten A-Z mayusculas "
                        f"(sin tildes ni N con virgulilla)")
        if not (4 <= len(w) <= MAX_LEN):
            errs.append(f"[{i}] '{w}': longitud {len(w)} fuera de 4..{MAX_LEN}")
        if i < N_HARD and len(w) < HARD_MIN_LEN:
            errs.append(f"[{i}] '{w}': longitud {len(w)} < {HARD_MIN_LEN}; "
                        f"los indices 0..{N_HARD-1} son del modo DIFICIL")
        if i >= N_HARD and len(w) >= HARD_MIN_LEN:
            errs.append(f"[{i}] '{w}': longitud {len(w)} >= {HARD_MIN_LEN}; "
                        f"los indices {N_HARD}..{N_WORDS-1} deben ser de 4 o 5")

    return errs


def emit_sv(words):
    lines = []
    a = lines.append

    a("// =====================================================================")
    a("// word_rom.sv - Banco de palabras del Ahorcado")
    a("//")
    a("// ARCHIVO GENERADO AUTOMATICAMENTE. No editar a mano.")
    a("// Fuente: python/gen_word_rom.py")
    a("// Regenerar con: python gen_word_rom.py")
    a("//")
    a("// Orden del banco (de esto depende la seleccion del indice):")
    a(f"//   indices  0..{N_HARD-1} -> longitud >= {HARD_MIN_LEN} (DIFICIL y FACIL)")
    a(f"//   indices {N_HARD}..{N_WORDS-1} -> longitud 4 o 5      (solo FACIL)")
    a("//")
    a("// Empaquetado de word_data_o:")
    a("//   El caracter de la posicion i (i = 0 es el primero de la palabra)")
    a("//   ocupa word_data_o[8*(MAX_LEN-1-i) +: 8]. El primer caracter queda")
    a("//   en los bits mas significativos, lo que permite escribir cada")
    a("//   palabra como un literal de texto legible y revisable.")
    a("//   Las posiciones posteriores a word_len_o se rellenan con 8'h20.")
    a("//")
    a("// Lectura combinacional; el consumidor la registra en START_GAME.")
    a("// =====================================================================")
    a("")
    a("module word_rom #(")
    a(f"    parameter int N_WORDS = {N_WORDS},")
    a(f"    parameter int MAX_LEN = {MAX_LEN}")
    a(") (")
    a("    input  logic [5:0]              index_i,")
    a("    output logic [8*MAX_LEN-1:0]    word_data_o,")
    a("    output logic [3:0]              word_len_o")
    a(");")
    a("")
    a("    always_comb begin")
    a("        unique case (index_i)")

    for i, w in enumerate(words):
        padded = w.ljust(MAX_LEN)
        tag = "DIFICIL" if i < N_HARD else "FACIL  "
        a(f'            6\'d{i:<2} : begin word_data_o = "{padded}";'
          f' word_len_o = 4\'d{len(w):<2}; end  // {tag} {w}')

    a("            default: begin word_data_o = \"            \";"
      " word_len_o = 4'd0;  end")
    a("        endcase")
    a("    end")
    a("")
    a("endmodule")
    a("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="solo validar, no escribir")
    args = ap.parse_args()

    errs = validate(WORDS)
    if errs:
        print("FAIL - el banco de palabras no es valido:")
        for e in errs:
            print("  -", e)
        return 1

    hard = WORDS[:N_HARD]
    easy = WORDS[N_HARD:]
    print("PASS - banco de palabras valido")
    print(f"  palabras totales      : {len(WORDS)} (minimo exigido: 50)")
    print(f"  validas para DIFICIL  : {len(hard)} "
          f"(longitudes {min(map(len,hard))}..{max(map(len,hard))})")
    print(f"  solo FACIL            : {len(easy)} "
          f"(longitudes {min(map(len,easy))}..{max(map(len,easy))})")
    print(f"  longitud maxima       : {max(map(len,WORDS))} (permitida: {MAX_LEN})")
    print(f"  almacenamiento        : {N_WORDS*(8*MAX_LEN+4)} bits")

    if args.check:
        return 0

    raiz = Path(__file__).resolve().parents[2]   # DESIGN -> PYTHON -> raiz del repo
    out = (raiz / "Ahorcado_juego_electrónico_FPGA_y_PC_por_enlace_serial"
                / "FPGA" / "DESIGN" / "word_rom.sv")
    out.write_text(emit_sv(WORDS), encoding="utf-8")
    print(f"  generado              : {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
