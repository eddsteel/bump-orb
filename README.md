# Bump orbs action

This action checks for updates to the orbs used in the given Circle CI configuration file. It may use a token to also check for updates to private orbs if provided. This is powered by the `circleci orbs list <namespace>` command, whose output is parsed and compared with the current defined versions. If a version has a non-production version specified (with the `<orb name>@dev:<commit>` syntax) it will be skipped.

## Inputs

### `config`

The filename to check, relative to the root of the workspace. By default this is `.circleci/config.yml` but it may be useful to configure if you have multiple workflows defined.

### `token`

The token used for authentication when running `circleci orbs list --private`. If provided, private orbs are checked for all namespaces, even though the token is probably only going to provide access to one of them.

## Outputs

### `summary`

A list of changed orbs, in markdown format. This is suitable for embedding in an automatic PR.

## Example usage


```yaml
jobs:
  bumporbs:
    name: Bump orbs
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: write
      pull-requests: write
    steps:
    - name: Checkout repository
      uses: actions/checkout@v3
    - name: Bump orb versions
      id: borb
      uses: eddsteel/bump-orb@v1
      with:
        token: ${{ secrets.CIRCLECI_TOKEN }}
    - name: Create PR
      uses: peter-evans/create-pull-request@v4
      with:
        add-paths: ".circleci/*"
        branch: bump-orbs
        commit-message: "Bump CircleCI orbs"
        title: "Bump CircleCI orbs"
        body: "${{ steps.borb.outputs.summary }}"
        labels: |
          dependencies
```
