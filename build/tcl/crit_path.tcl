open_project D:/Software/Xiaomi_MiMo/video/zynq_video_pipeline/vivado/zynq_video_pipeline.xpr
open_run impl_1
set paths [get_timing_paths -max_paths 8 -nworst 1]
foreach p \ {
  puts [format {SLACK=%.3f START=%s END=%s} [get_property SLACK \] [get_property STARTPOINT \] [get_property ENDPOINT \]]
}
