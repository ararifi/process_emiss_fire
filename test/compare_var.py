"""Compare processed (regridded) GFED_NRT emissions against the original
download for a given MODE and variable.

Produces, in test/plots/:
  - <MODE>_<VAR>_<YEAR>_mapplot.png       two-panel global mean map
  - <MODE>_<YEAR>_timeseries_<VAR>.png    daily global-mean time series + table
"""

import os
import sys
import glob
import numpy as np
import xarray as xr
import matplotlib.pyplot as plt
from scipy.interpolate import griddata

import matplotlib as mpl
mpl.use("Agg")
import cartopy.crs as ccrs
import psyplot.project as psy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "notebooks"))
from helper import source_env  # noqa: E402

source_env(os.path.join(HERE, "..", "env.sh"))


def load_processed(mode: str, varname: str, year: int) -> xr.DataArray:
    root = os.environ["output_root"]
    pattern = f"{root}/{mode}/GFED_NRT/daily/{year}/*{varname}*.nc"
    files = sorted(glob.glob(pattern))
    if not files:
        raise FileNotFoundError(pattern)
    ds = xr.open_mfdataset(
        files, combine="by_coords", parallel=False,
        chunks={"time": 30}, data_vars="minimal", coords="minimal",
        compat="override",
    )
    return ds["emiss_fire"]


def load_original(varname: str, year: int) -> xr.DataArray:
    root = os.environ["input_root"]
    grid_area = os.environ["input_eco"]
    files = sorted(glob.glob(f"{root}/GFED_NRT/daily/{year}/*.nc"))
    if not files:
        raise FileNotFoundError(f"{root}/GFED_NRT/daily/{year}")
    ds = xr.open_mfdataset(
        files, combine="by_coords", parallel=False,
        chunks={"time": 30}, data_vars="minimal", coords="minimal",
        compat="override",
    )
    da = ds[varname]
    area = xr.open_dataarray(grid_area)
    # g/day per cell -> kg m-2 s-1
    da = (da / area) * 1.157407407e-8
    da.name = varname
    return da


def icon_to_regular(da_t: xr.DataArray, nlon=720, nlat=360) -> xr.Dataset:
    """Interpolate an ICON unstructured field (cell dim) onto a regular grid."""
    lon = np.rad2deg(da_t.clon.values)
    lat = np.rad2deg(da_t.clat.values)
    lon = np.where(lon > 180, lon - 360, lon)

    lon_reg = np.linspace(-180, 180, nlon)
    lat_reg = np.linspace(-90, 90, nlat)
    lon2d, lat2d = np.meshgrid(lon_reg, lat_reg)
    data_reg = griddata((lon, lat), da_t.values, (lon2d, lat2d), method="linear")
    return xr.Dataset(
        {"emiss_fire": (["lat", "lon"], data_reg)},
        coords={"lat": lat_reg, "lon": lon_reg},
    )


def make_mapplot(mode: str, varname: str, year: int,
                 da_p: xr.DataArray, da_d: xr.DataArray, out_path: str):
    da_p_t = da_p.mean(dim="time").compute()
    da_d_t = da_d.mean(dim="time").compute()

    if mode == "icon":
        ds_left = icon_to_regular(da_p_t)
    else:
        ds_left = da_p_t.to_dataset(name="emiss_fire")

    ds_right = da_d_t.to_dataset(name=varname)

    # Shared color scale from the processed (regridded) field.
    vals = ds_left["emiss_fire"].values
    vmin = float(np.nanpercentile(vals, 2))
    vmax = float(np.nanpercentile(vals, 99.6))

    fig = plt.figure(figsize=(16, 6))
    proj = ccrs.Robinson()
    ax_left = fig.add_subplot(1, 2, 1, projection=proj)
    ax_right = fig.add_subplot(1, 2, 2, projection=proj)

    psy.plot.mapplot(
        ds_left, name="emiss_fire", ax=ax_left,
        cmap="viridis", projection="robin",
        title=f"Processed ({mode}) — {varname} mean {year} [kg m-2 s-1]",
        bounds={"method": "minmax", "vmin": vmin, "vmax": vmax},
    )
    psy.plot.mapplot(
        ds_right, name=varname, ax=ax_right,
        cmap="viridis", projection="robin",
        title=f"Original (GFED NRT) — {varname} mean {year} [kg m-2 s-1]",
        bounds={"method": "minmax", "vmin": vmin, "vmax": vmax},
    )

    fig.suptitle(f"{varname} — Processed vs. Original ({mode}, {year})",
                 fontsize=14, y=1.02)
    fig.savefig(out_path, dpi=120, bbox_inches="tight")
    psy.close("all")
    plt.close(fig)
    print(f"wrote {out_path}")


def make_timeseries(mode: str, varname: str, year: int,
                    da_p: xr.DataArray, da_d: xr.DataArray, out_path: str):
    if mode == "icon":
        ts_p = da_p.mean(dim="cell").compute()
    else:
        ts_p = da_p.mean(dim=["lon", "lat"]).compute()
    ts_d = da_d.mean(dim=["lon", "lat"]).compute()

    fig, (ax, ax_tbl) = plt.subplots(
        2, 1, figsize=(12, 7),
        gridspec_kw={"height_ratios": [3, 1]},
    )

    ax.plot(ts_p["time"].values, ts_p.values,
            label=f"Processed ({mode})", color="C0", lw=1.5)
    ax.plot(ts_d["time"].values, ts_d.values,
            label="Original (GFED NRT)", color="C3", lw=1.0, alpha=0.8)
    ax.set_xlabel("Date")
    ax.set_ylabel(f"{varname} global mean flux [kg m$^{{-2}}$ s$^{{-1}}$]")
    ax.set_title(f"{varname} daily global-mean time series — {mode}, {year}")
    ax.legend(loc="best")
    ax.grid(True, alpha=0.3)

    def stats(a):
        v = np.asarray(a.values, dtype=float)
        return [np.nanmean(v), np.nanmin(v), np.nanmax(v), np.nanstd(v)]

    p_stats = stats(ts_p)
    d_stats = stats(ts_d)
    # correlation between the two daily series, after aligning on time
    ts_p_a, ts_d_a = xr.align(ts_p, ts_d, join="inner")
    a = np.asarray(ts_p_a.values, dtype=float)
    b = np.asarray(ts_d_a.values, dtype=float)
    m = np.isfinite(a) & np.isfinite(b)
    corr = float(np.corrcoef(a[m], b[m])[0, 1]) if m.sum() > 2 else np.nan
    rel_bias = (np.nanmean(a[m]) - np.nanmean(b[m])) / np.nanmean(b[m]) \
        if m.sum() > 2 else np.nan

    ax_tbl.axis("off")
    cell_text = [
        [f"{p_stats[0]:.3e}", f"{d_stats[0]:.3e}"],
        [f"{p_stats[1]:.3e}", f"{d_stats[1]:.3e}"],
        [f"{p_stats[2]:.3e}", f"{d_stats[2]:.3e}"],
        [f"{p_stats[3]:.3e}", f"{d_stats[3]:.3e}"],
        [f"{corr:.4f}", ""],
        [f"{rel_bias:+.2%}", ""],
    ]
    table = ax_tbl.table(
        cellText=cell_text,
        rowLabels=["mean", "min", "max", "std",
                   "corr(processed, original)", "rel. bias (P-O)/O"],
        colLabels=[f"Processed ({mode})", "Original"],
        loc="center", cellLoc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1.0, 1.4)

    fig.tight_layout()
    fig.savefig(out_path, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {out_path}")


def run(mode: str, varname: str, year: int, plots_dir: str):
    os.makedirs(plots_dir, exist_ok=True)
    da_p = load_processed(mode, varname, year)
    da_d = load_original(varname, year)

    map_path = os.path.join(plots_dir, f"{mode}_{varname}_{year}_mapplot.png")
    ts_path = os.path.join(plots_dir, f"{mode}_{varname}_{year}_timeseries.png")
    make_mapplot(mode, varname, year, da_p, da_d, map_path)
    make_timeseries(mode, varname, year, da_p, da_d, ts_path)


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--mode", default="icon", choices=["icon", "r1x1"])
    p.add_argument("--var", default="OC")
    p.add_argument("--year", type=int, default=2024)
    p.add_argument("--plots-dir",
                   default=os.path.join(HERE, "plots"))
    args = p.parse_args()
    run(args.mode, args.var, args.year, args.plots_dir)