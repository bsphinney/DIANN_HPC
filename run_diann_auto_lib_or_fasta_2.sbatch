#!/bin/bash -l
#SBATCH --job-name=diann_multi_fasta
#SBATCH --cpus-per-task=64
#SBATCH --mem=512G
#SBATCH --time=24:00:00
#SBATCH -o diann.%j.out
#SBATCH -e diann.%j.err
#SBATCH --account=genome-center-grp
#SBATCH --time=24:00:00
#SBATCH --partition=high

# -------------------- USER PATHS --------------------
WORKDIR=/quobyte/proteomics-grp/brett/OT_flex_salmon
IMG=$WORKDIR/diann2.3.0.sif
DATA_DIR=$WORKDIR/data
FASTA_DIR=$WORKDIR/fasta
LIB_DIR=$WORKDIR/lib
OUTDIR=$WORKDIR/out

mkdir -p "$OUTDIR"

module load apptainer

# -------------------- BUILD RUN FILE LIST --------------------
RUN_ARGS=""
for f in "$DATA_DIR"/*.d "$DATA_DIR"/*.raw "$DATA_DIR"/*.mzML; do
  [ -e "$f" ] || continue
  RUN_ARGS+=" --f /work/data/$(basename "$f")"
done
if [ -z "$RUN_ARGS" ]; then
  echo "No MS files found in $DATA_DIR"
  exit 1
fi

# ----- BUILD FASTA LIST (used by both library and library-free modes) -----
FASTA_ARGS=""
for fa in "$FASTA_DIR"/*.fasta "$FASTA_DIR"/*.fa; do
  [ -e "$fa" ] || continue
  FASTA_ARGS+=" --fasta /work/fasta/$(basename "$fa")"
done

# -------------------- DETECT SPECTRAL LIBRARY --------------------
SPECLIB_FILE=$(ls "$LIB_DIR"/*.speclib 2>/dev/null | head -n 1)

# -------------------- IF SPECTRAL LIBRARY FOUND --------------------
if [ -n "$SPECLIB_FILE" ]; then
  echo "Spectral library detected: $SPECLIB_FILE"
  echo "Running DIA-NN in library mode..."

  apptainer exec --bind $WORKDIR:/work $IMG /diann-2.3.0/diann-linux \
    $RUN_ARGS \
    $FASTA_ARGS \
    --lib /work/lib/$(basename "$SPECLIB_FILE") \
    --threads 64 \
    --verbose 1 \
    --out $OUTDIR/report.parquet \
    --qvalue 0.01 \
    --matrices \
    --out-lib $OUTDIR/report-lib.parquet \
    --gen-spec-lib \
    --xic \
    --unimod4 \
    --var-mods 1 \
    --window 6 \
    --mass-acc 14 \
    --mass-acc-ms1 14 \
    --peptidoforms \
    --reanalyse \
    --rt-profiling \
	--use-quant

# -------------------- ELSE RUN FASTA SEARCH --------------------
else
  echo "No spectral library found. Running library-free FASTA search..."

  if [ -z "$FASTA_ARGS" ]; then
    echo "No FASTA files found in $FASTA_DIR"
    exit 1
  fi

  apptainer exec --bind $WORKDIR:/work $IMG /diann-2.3.0/diann-linux \
    $RUN_ARGS \
    $FASTA_ARGS \
  --out $OUTDIR/report.parquet \
  --out-lib $OUTDIR/report-lib.parquet \
  --matrices \
  --fasta-search \
  --qvalue 0.01 \
  --gen-spec-lib \
  --verbose 1 \
  --gen-spec-lib \
  --predictor \
  --xic \
  --threads 64 \
  --met-excision \
  --min-pep-len 7 \
  --max-pep-len 30 \
  --min-pr-mz 300 \
  --max-pr-mz 1200 \
  --min-pr-charge 1 \
  --max-pr-charge 4 \
  --min-fr-mz 200 \
  --max-fr-mz 1200 \
  --cut K*,R* \
  --missed-cleavages 1 \
  --unimod4 \
  --var-mods 1 \
  --window 6 \
  --mass-acc 14 \
  --mass-acc-ms1 14 \
  --reanalyse \
  --rt-profiling 
fi

echo "DIA-NN analysis complete. Results saved in $OUTDIR"
