# git-dep-dup

Same as `git-dep`, but where a git dependency is added multiple times:

* two crates have the same dep at the same commit (crate-a, crate-c)
* a third crate has the same dep at a different commit (crate-b)
