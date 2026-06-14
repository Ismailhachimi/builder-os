Inspect the repository, present a short plan, then add a `group_by_status`
function to `tickets.py`. It must preserve ticket order within each group,
return a normal dictionary, and reject tickets without a non-empty string
`status` by raising `ValueError`. Add focused tests and run the full test suite.
