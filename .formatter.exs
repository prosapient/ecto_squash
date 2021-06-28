# Used by "mix format"
pattern = ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
exclude_prefix = "test/fixtures"

[
  inputs:
    Enum.flat_map(
      pattern,
      &Path.wildcard(&1, match_dot: true)
    )
    |> Enum.reject(fn path ->
      String.starts_with?(path, exclude_prefix)
    end)
]
