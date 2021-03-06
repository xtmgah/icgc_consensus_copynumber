#' 
#' This script produces the final consensus profiles that are ready to be released. It does:
#' * Strip the unneeded columns from the interim consensus profiles to create the PCAWG-wide release of clonal copy number
#' * Annotate the interim consensus profiles to create the PCAWG-11 release with subclonal calls from every method annotated
#' 
#' It needs a combined purity and overrulings table as input, created from the summary stats files
#' 

get_entry_template = function(map, methodname) {
  
  are_null = unlist(lapply(map$cn_states, is.null))
  are_na = unlist(lapply(map$cn_states, is.na))
  first_not_null = which(!are_null & !are_na)[1]
  template = map$cn_states[[first_not_null]][[1]]
  # } else {
  #   stop(paste0("Could not find template for ", methodname))
  # }
  template[1,1:ncol(template)] = NA
  return(template)
}

#' Function that adds a line of NAs for missing (i.e. NULL) mapped entries
#' this convenience function is used to make the cn_states list have the same
#' number of entries as the segments it was mapped to. do.call(rbind,) does
#' not insert a line when the list entry is NULL
padd_empty_entries = function(map, methodname) {
  template = get_entry_template(map, methodname) 
  
  cn_states = list()
  for (i in 1:length(map$cn_states)) {
    if (is.null(map$cn_states[[i]]) | is.na(map$cn_states[[i]])) {
      cn_states[[i]] = template
    } else {
      if (methodname=="Sclust" & nrow(map$cn_states[[i]][[1]])==1) {
        cn_states[[i]] = map$cn_states[[i]][[1]]
      } else if (methodname=="Sclust") {
        cn_states[[i]] = template
      } else {
        cn_states[[i]] = map$cn_states[[i]][[1]]
      }
    }
  }
  return(cn_states)
}

#' Function to sanity check the final mapping
check_mapping = function(dat, anno, methodname) {
  anno_temp = anno
  are_na = is.na(anno_temp[,1])
  anno_temp[are_na,1:3] = dat[are_na, 1:3]
  dat_gr = makeGRdat_gr = makeGRangesFromDataFrame(dat)
  anno_gr = makeGRangesFromDataFrame(anno_temp, 
                                     seqnames.field=paste0(methodname, "_chromosome"), 
                                     start.field=paste0(methodname, "_start"), 
                                     end.field=paste0(methodname, "_end"))
  overlap = findOverlaps(anno_gr, dat_gr)
  
  # For every segment in anno there must be a segment in dat
  # with which it overlaps and that has the same index number
  # Even if segments have been merged, the first "subsegment" 
  # of that merge should have the same id as the anno seg.
  res = lapply(1:nrow(dat), function(i) {
    if (any(queryHits(overlap)[subjectHits(overlap)==i]==i)) {
      TRUE
    } else {
      FALSE
    }
  })
  if (!all(unlist(res))) {
    all_verdicts = unlist(res)
    stop(paste0("No overlapping segment for segment(s) ", which(!all_verdicts)))
  }
}

#' Append extra lines in case a last segment was not called and sanity check the result
make_anno_complete = function(anno, dat, map, num_segments, methodname) {
  if (nrow(anno) < num_segments) {
    template = get_entry_template(map)
    colnames(template) = colnames(anno)
    for (i in 1:(num_segments-nrow(anno))) {
      anno = rbind(anno, template)
    }
  }
  
  check_mapping(dat, anno, methodname)
  anno = anno[,c(4:ncol(anno))]
  return(anno)
}

reset_overruled_annotations = function(anno, overrulings_pivot, methodid) {
  if (nrow(overrulings_pivot) > 0) {
    if (overrulings_pivot[1, methodid]) {
      anno[1:nrow(anno), 1:ncol(anno)] = NA
    }
  }
  return(anno)
}

combine_all_annotations = function(all_annotations, overrulings_pivot, num_segments) {
  if (!is.na(all_annotations$map_vanloowedge)) {
    if (all(unlist(lapply(all_annotations$map_vanloowedge$cn_states, function(x) nrow(x[[1]]))) == 1)) {
      anno_vanloowedge = do.call(rbind, padd_empty_entries(all_annotations$map_vanloowedge, "Battenberg"))
      colnames(anno_vanloowedge) = paste0("battenberg_", colnames(anno_vanloowedge))
    } else {
      print("Found too many annotations for some segments from Battenberg")
    }
    anno_vanloowedge = make_anno_complete(anno_vanloowedge, dat, all_annotations$map_vanloowedge, num_segments, "battenberg")
  } else {
    anno_vanloowedge = data.frame(matrix(NA, num_segments, 10))
    colnames(anno_vanloowedge) = c("nMaj1_A", "nMin1_A", "frac1_A", "nMaj2_A", "nMin2_A", "frac2_A", "SDfrac_A", "SDfrac_A_BS", "frac1_A_0.025", "frac1_A_0.975")
    colnames(anno_vanloowedge) = paste0("battenberg_", colnames(anno_vanloowedge))
  }
  
  if (!is.na(all_annotations$map_broad)) {
    if (all(unlist(lapply(all_annotations$map_broad$cn_states, function(x) nrow(x[[1]]))) == 1, na.rm=T)) {
      anno_broad = do.call(rbind, padd_empty_entries(all_annotations$map_broad, "ABSOLUTE"))
      colnames(anno_broad) = paste0("absolute_", colnames(anno_broad))
    } else {
      print("Found too many annotations for some segments from ABSOLUTE")
    }
    anno_broad = make_anno_complete(anno_broad, dat, all_annotations$map_broad, num_segments, "absolute")
  } else {
    anno_broad = data.frame(matrix(NA, num_segments, 4))
    colnames(anno_broad) = c("broad_major_cn", "broad_minor_cn", "broad_het_error", "broad_cov_error")
    colnames(anno_broad) = paste0("absolute_", colnames(anno_broad))
  }
  
  colnames_dkfz = c("copy_number", "minor_cn", "major_cn", "cellular_prevalence", "dh", "covRatio")
  if (!is.na(all_annotations$map_dkfz)) {
    if (all(unlist(lapply(all_annotations$map_dkfz$cn_states, function(x) nrow(x[[1]]))) == 1)) {
      anno_dkfz = do.call(rbind, padd_empty_entries(all_annotations$map_dkfz, "ACEseq"))
      colnames(anno_dkfz) = paste0("aceseq_", colnames(anno_dkfz))
    } else {
      print("Found too many annotations for some segments from ACEseq")
    }
    anno_dkfz = make_anno_complete(anno_dkfz, dat, all_annotations$map_dkfz, num_segments, "aceseq")
  } else {
    anno_dkfz = data.frame(matrix(NA, num_segments, length(colnames_dkfz)))
    colnames(anno_dkfz) = colnames_dkfz
    colnames(anno_dkfz) = paste0("aceseq_", colnames(anno_dkfz))
  }
  anno_dkfz = anno_dkfz[,  paste0("aceseq_",c("copy_number", "minor_cn", "major_cn"))]
  
  colnames_mustonen = c("copy_number", "minor_cn", "major_cn", "clonal_frequency")
  if (!is.na(all_annotations$map_mustonen)) {
    if (all(unlist(lapply(all_annotations$map_mustonen$cn_states, function(x) nrow(x[[1]]))) == 1)) {
      anno_mustonen = do.call(rbind, padd_empty_entries(all_annotations$map_mustonen, "CloneHD"))
      anno_mustonen$ccf = 1
      colnames(anno_mustonen) = paste0("clonehd_", colnames(anno_mustonen))
    } else {
      print("Found too many annotations for some segments from CloneHD")
    }
    anno_mustonen = make_anno_complete(anno_mustonen, dat, all_annotations$map_mustonen, num_segments, "clonehd")
  } else {
    anno_mustonen = data.frame(matrix(NA, num_segments, length(colnames_mustonen)))
    colnames(anno_mustonen) = colnames_mustonen
    colnames(anno_mustonen) = paste0("clonehd_", colnames(anno_mustonen))
  }
  anno_mustonen = anno_mustonen[, paste0("clonehd_", c("copy_number", "minor_cn", "major_cn"))]
  
  colnames_jabba = c("copy_number", "minor_cn", "major_cn", "cellular_prevalence")
  if (!is.na(all_annotations$map_jabba)) {
    if (all(unlist(lapply(all_annotations$map_jabba$cn_states, function(x) nrow(x[[1]]))) == 1)) {
      anno_jabba = do.call(rbind, padd_empty_entries(all_annotations$map_jabba, "JaBbA"))
      anno_jabba$ccf = 1
      colnames(anno_jabba) = paste0("jabba_", colnames(anno_jabba))
    } else {
      print("Found too many annotations for some segments from JaBbA")
    }
    anno_jabba = make_anno_complete(anno_jabba, dat, all_annotations$map_jabba, num_segments, "jabba")
  } else {
    anno_jabba = data.frame(matrix(NA, num_segments, 4))
    colnames(anno_jabba) = colnames_jabba
    colnames(anno_jabba) = paste0("jabba_", colnames(anno_jabba))
  }
  anno_jabba = anno_jabba[, paste0("jabba_", c("copy_number", "minor_cn", "major_cn"))]
  
  # Sclust setup adapted. The padd_empty_entries function removes any problematic mappings
  # This is due to the segmentation of Sclust being far too lenient in positions
  if (!is.na(all_annotations$map_peifer)) {
    #if (all(unlist(lapply(all_annotations$map_peifer$cn_states, function(x) nrow(x[[1]]))) == 1)) {
      anno_peifer = do.call(rbind, padd_empty_entries(all_annotations$map_peifer, "Sclust"))
      colnames(anno_peifer) = paste0("sclust_", colnames(anno_peifer))
    #} else {
    #  print("Found too many annotations for some segments from Sclust")
      # anno_peifer = data.frame(matrix(NA, num_segments, 9))
      # colnames(anno_peifer) = c("chromosome", "start", "end", "nMaj1_A", "nMin1_A", "frac1_A", "nMaj2_A", "nMin2_A", "frac2_A")
      # colnames(anno_peifer) = paste0("sclust_", colnames(anno_peifer))
    #}
    anno_peifer = make_anno_complete(anno_peifer, dat, all_annotations$map_peifer, num_segments, "sclust")
  } else {
    anno_peifer = data.frame(matrix(NA, num_segments, 6))
    colnames(anno_peifer) = c("nMaj1_A", "nMin1_A", "frac1_A", "nMaj2_A", "nMin2_A", "frac2_A")
    colnames(anno_peifer) = paste0("sclust_", colnames(anno_peifer))
  }
  
  # Check for whether a method has been overruled and reset annotations if needed
  anno_broad = reset_overruled_annotations(anno_broad, overrulings_pivot, "broad")
  anno_dkfz = reset_overruled_annotations(anno_dkfz, overrulings_pivot, "dkfz")
  anno_vanloowedge = reset_overruled_annotations(anno_vanloowedge, overrulings_pivot, "vanloowedge")
  anno_mustonen = reset_overruled_annotations(anno_mustonen, overrulings_pivot, "mustonen")
  anno_peifer = reset_overruled_annotations(anno_peifer, overrulings_pivot, "peifer")
  anno_jabba = reset_overruled_annotations(anno_jabba, overrulings_pivot, "jabba")
  
  return(data.frame(anno_broad, anno_dkfz, anno_vanloowedge, anno_mustonen, anno_peifer, anno_jabba))
}


# samplename = "6aa00162-6294-4ce7-b6b7-0c3452e24cd6"


args = commandArgs(T)
libpath = args[1]
samplename = args[2]
outdir = args[3]
sex = args[4]

source(file.path(libpath, "util.R"))
num_threads = 6

# samplename = "005e85a3-3571-462d-8dc9-2babfc7ace21"
# outdir = "output/"
# sex = "male"

current_date = gsub("-", "", Sys.Date())

cons_profile_file = file.path("output/consensus_profile", paste0(samplename, "_consensus_profile.txt"))
summary_stats_file = file.path("output/summary_stats/", paste0(samplename, "_summary_stats.txt"))

purity_overrulings_file = "data_bundle/icgc_purity_overrulings.txt"
purity_and_ploidy_overrulings_file = "data_bundle/icgc_purity_and_ploidy_overrulings.txt"
breakpoints_file = file.path("data_bundle/consensus_breakpoints", paste0(samplename, ".txt"))

# overrulings_pivot = as.data.frame(readr::read_tsv("manual_review_overrulings_pivot_table.txt"))
# overrulings_pivot = overrulings_pivot[overrulings_pivot$samplename==samplename,]

summ_stats = readr::read_tsv(summary_stats_file)
# purity_overrulings = readr::read_tsv(purity_overrulings_file)
purity_and_ploidy_overrulings = readr::read_tsv(purity_and_ploidy_overrulings_file)
summ_stats = summ_stats[summ_stats$samplename==samplename,]
# purity_overrulings = purity_overrulings[purity_overrulings$samplename==samplename,]
purity_and_ploidy_overrulings = purity_and_ploidy_overrulings[purity_and_ploidy_overrulings$samplename==samplename,]

# Assemble overrulings into a single data frame
overrulings = summ_stats[1,grepl("exclude", colnames(summ_stats))]
colnames(overrulings) = stringr::str_replace(colnames(overrulings), "exclude_", "")
overrulings_pivot = overrulings | purity_and_ploidy_overrulings[colnames(overrulings)]


if (file.exists(cons_profile_file) & file.exists(breakpoints_file)) {
  print("Reading in and mapping data...")
  dat = read.table(cons_profile_file, header=T, stringsAsFactors=F)  
  breakpoints = read.table(breakpoints_file, header=T, stringsAsFactors=F)
  segments = breakpoints2segments(breakpoints)

  data_bundle_profiles_path = "data_bundle/input_profiles/"
  dkfz_segmentsfile = file.path(data_bundle_profiles_path, paste0("dkfz/annotations/", samplename, "_annotations.txt"))
  dkfz_purityfile = file.path(data_bundle_profiles_path, paste0("dkfz/purity_ploidy.txt"))
  vanloowedge_segmentsfile = file.path(data_bundle_profiles_path, paste0("vanloo_wedge/annotations/", samplename, "_annotations.txt"))
  vanloowedge_purityfile = file.path(data_bundle_profiles_path, paste0("vanloo_wedge/purity_ploidy.txt"))
  peifer_segmentsfile = file.path(data_bundle_profiles_path, paste0("peifer_annotations/", samplename, "_annotations.txt"))
  peifer_purityfile = file.path(data_bundle_profiles_path, paste0("peifer/purity/ploidy.txt"))
  mustonen_segmentsfile = file.path(data_bundle_profiles_path, paste0("mustonen/annotations/", samplename, "_annotations.txt"))
  mustonen_purityfile = file.path(data_bundle_profiles_path, paste0("mustonen/purity_ploidy.txt"))
  broad_segmentsfile = file.path(data_bundle_profiles_path, paste0("broad/annotations/", samplename, "_annotations.txt"))
  broad_purityfile = file.path(data_bundle_profiles_path, paste0("broad/purity_ploidy.txt"))
  jabba_segmentsfile = file.path(data_bundle_profiles_path, paste0("jabba/annotations/", samplename, "_annotations.txt"))
  jabba_purityfile = file.path(data_bundle_profiles_path, paste0("jabba/purity_ploidy.txt"))
  
  method_segmentsfile = list(dkfz=dkfz_segmentsfile,
                             vanloowedge=vanloowedge_segmentsfile,
                             peifer=peifer_segmentsfile,
                             mustonen=mustonen_segmentsfile,
                             broad=broad_segmentsfile,
                             jabba=jabba_segmentsfile)
  
  method_purityfile = list(dkfz=dkfz_purityfile,
                           vanloowedge=vanloowedge_purityfile,
                           peifer=peifer_purityfile,
                           mustonen=mustonen_purityfile,
                           broad=broad_purityfile,
                           jabba=jabba_purityfile)
  
  # dat = na.omit(dat)
  dat$total_cn = dat$major_cn+dat$minor_cn
  dat = dat[, c("chromosome", "start", "end", "total_cn", "major_cn", "minor_cn", "star", "level", "methods_agree")]
  
  # Map the annotations against the loaded consensus profile
  all_annotations = parse_all_profiles(samplename=samplename, 
                                       segments=dat, 
                                       method_segmentsfile=method_segmentsfile, 
                                       method_purityfile=method_purityfile, 
                                       method_baflogr=NULL, 
                                       sex=sex,
                                       mustonen_has_header=F,
                                       num_threads=num_threads)  
  combined_annotations = combine_all_annotations(all_annotations, overrulings_pivot, nrow(dat))
  
  # PCAWG11 profile with full annotations
  dat = data.frame(dat, combined_annotations)
  write.table(dat, file=file.path(outdir, "pcawg11_consensus_profile", paste0(samplename, ".consensus.", current_date, ".somatic.cna.annotated.txt")), quote=F, row.names=F, sep="\t")
  
  # PCAWG-wide profile
  dat = dat[, c("chromosome", "start", "end", "total_cn", "major_cn", "minor_cn", "star")]
  write.table(dat, file=file.path(outdir, "consensus_profile_final", paste0(samplename, ".consensus.", current_date, ".somatic.cna.txt")), quote=F, row.names=F, sep="\t")
}
