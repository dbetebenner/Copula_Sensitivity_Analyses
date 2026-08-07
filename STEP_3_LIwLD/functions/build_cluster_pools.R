############################################################################
###
### build_cluster_pools
###
### Construct growth-stratified super-district pools (Low/Typical/High)
### within a condition using district-level true mean SGPc.
###
############################################################################

build_cluster_pools <- function(
  pairs,
  sg_col,
  u_full,
  v_full,
  p1_copula,
  condition_id,
  n_growth_strata = 3L,
  min_pool_n = 500L,
  scale = "percentile"
) {
  if (!is.data.table(pairs)) {
    pairs <- as.data.table(pairs)
  }

  if (!(sg_col %in% names(pairs))) {
    return(list(
      pools = list(),
      district_stats = data.table(),
      stratum_stats = data.table()
    ))
  }

  n_growth_strata <- as.integer(n_growth_strata)
  if (!is.finite(n_growth_strata) || n_growth_strata < 2L) {
    n_growth_strata <- 3L
  }
  min_pool_n <- as.integer(min_pool_n)
  if (!is.finite(min_pool_n) || min_pool_n < 1L) {
    min_pool_n <- 1L
  }

  district_index <- pairs[,
    .(idx = list(.I), n_district = .N),
    by = sg_col
  ][order(-n_district)]
  if (nrow(district_index) < n_growth_strata) {
    return(list(
      pools = list(),
      district_stats = data.table(),
      stratum_stats = data.table()
    ))
  }

  district_stats <- district_index[,
    {
      sg_idx <- idx[[1L]]
      sgpc <- sgpc_engine(
        u_full[sg_idx],
        v_full[sg_idx],
        p1_copula,
        scale = scale
      )
      list(
        idx = idx,
        n_district = as.double(n_district),
        true_mean_sgpc = as.double(mean(sgpc, na.rm = TRUE)),
        true_median_sgpc = as.double(median(sgpc, na.rm = TRUE))
      )
    },
    by = sg_col
  ]

  district_stats <- district_stats[order(true_mean_sgpc, na.last = TRUE)]
  district_stats[,
    growth_rank := frank(
      true_mean_sgpc,
      ties.method = "average",
      na.last = "keep"
    )
  ]
  district_stats[,
    stratum_id := as.integer(cut(
      growth_rank,
      breaks = n_growth_strata,
      labels = FALSE,
      include.lowest = TRUE
    ))
  ]

  default_labels <- c("Low", "Typical", "High")
  if (n_growth_strata == 3L) {
    stratum_labels <- default_labels
  } else {
    stratum_labels <- paste0("Stratum", seq_len(n_growth_strata))
  }
  district_stats[,
    strata_label := stratum_labels[pmax(1L, pmin(n_growth_strata, stratum_id))]
  ]

  pool_rows <- district_stats[,
    {
      pooled_idx <- unlist(idx, use.names = FALSE)
      list(
        idx = list(pooled_idx),
        constituent_districts = paste(
          as.character(get(sg_col)),
          collapse = ","
        ),
        n_constituent_districts = as.double(.N),
        n_pool_raw = as.double(length(pooled_idx)),
        true_mean_sgpc = as.double(mean(true_mean_sgpc, na.rm = TRUE)),
        true_median_sgpc = as.double(median(true_median_sgpc, na.rm = TRUE))
      )
    },
    by = .(stratum_id, strata_label)
  ]

  pool_rows <- pool_rows[n_pool_raw >= min_pool_n]

  if (nrow(pool_rows) == 0) {
    return(list(
      pools = list(),
      district_stats = district_stats,
      stratum_stats = data.table()
    ))
  }

  pool_rows[,
    pool_id := paste0(
      condition_id,
      "__CLUSTER_",
      toupper(gsub("[^A-Za-z0-9]+", "_", strata_label))
    )
  ]

  pool_rows[,
    subgroup_id := paste0(
      "CLUSTER_",
      toupper(gsub("[^A-Za-z0-9]+", "_", strata_label))
    )
  ]
  pool_rows[, pool_type := "cluster"]

  pools <- lapply(seq_len(nrow(pool_rows)), function(i) {
    row <- pool_rows[i]
    list(
      id = row$subgroup_id,
      idx = row$idx[[1L]],
      pool_id = row$pool_id,
      pool_type = row$pool_type,
      strata_label = row$strata_label,
      constituent_districts = row$constituent_districts,
      n_constituent_districts = as.integer(row$n_constituent_districts),
      true_mean_sgpc = as.numeric(row$true_mean_sgpc),
      true_median_sgpc = as.numeric(row$true_median_sgpc)
    )
  })

  list(
    pools = pools,
    district_stats = district_stats,
    stratum_stats = pool_rows
  )
}
