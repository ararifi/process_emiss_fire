"""Run the processed-vs-original comparison for both ICON and r1x1 modes."""
import os
from compare_var import run

HERE = os.path.dirname(os.path.abspath(__file__))
PLOTS = os.path.join(HERE, "plots")

YEAR = 2024
VAR = "OC"

for mode in ("icon", "r1x1"):
    print(f"==> {mode}")
    run(mode, VAR, YEAR, PLOTS)