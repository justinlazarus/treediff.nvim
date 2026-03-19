if exists('g:loaded_treediff')
  finish
endif
let g:loaded_treediff = 1

command! -nargs=+ -complete=file TreeDiff lua require('treediff.diffview').open(<f-args>)
command! -nargs=0 TreeDiffOff lua require('treediff.diffview').close()
command! -nargs=? TreeDiffTest lua require('treediff.diffview').test(<f-args>)
