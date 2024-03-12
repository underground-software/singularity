### Contribution guidelines

- Rebase your changes on master
- No merge commits allowed
- Pull requests will not be squashed on merge
- Commits should stand on their own
    - Each commit should not break master (so tools like git bisect can work)
    - The message of each commit should clearly justify why the changes are necessary/useful
    - The amount of detail necessary in the commit message scales exponentially with the size of the actual diff
    - For that reason, small (and ideally atomic) commits are preferred to monolithic ones
        - i.e. where possible separate unrelated changes into more than one commit
        - separate refactoring/moving/renaming changes that do not affect observable behavior from functional changes that do
        - learn about and use: `git stash` `git add -p` `git commit --amend` `git commit --fixup` `git commit --rebase -i --autosquash`

### Philosophical concerns:

- The directories present at the top level of the repository represent boundaries. Be mindful when crossing them (is there a different solution?)
- The only code that should live in the top level itself (ideally) should be glue that holds the pieces together
