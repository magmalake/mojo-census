"""Seeds WAREHOUSE/mojo/repos with a few repos, for the lake smoke run.

    mojo run -I src libtins/smoke/seed_repos.mojo WAREHOUSE REPO...
"""

from std.sys import argv

from iceberg.batch import ColumnBuilder, batch_of_columns
from iceberg.catalog.filesystem import FilesystemCatalog
from iceberg.nested import ColumnTree
from iceberg.transforms import PartitionSpec
from iceberg.values import Datum

from lake import repos_schema, ts


def main() raises:
    var args = argv()
    var cat = FilesystemCatalog.local(String(args[1]))
    var s = repos_schema()
    var props = Dict[String, String]()
    var t = cat.create_table("mojo", "repos", s, PartitionSpec.unpartitioned(), props^)
    var repo = ColumnBuilder.of(s, 1)
    var first = ColumnBuilder.of(s, 3)
    var by = ColumnBuilder.of(s, 4)
    for i in range(2, len(args)):
        repo.add(Datum.string_(String(args[i])))
        first.add(ts(1_700_000_000_000_000))
        by.add(Datum.string_("seed"))
    var trees = List[ColumnTree]()
    trees.append(repo.build_tree())
    trees.append(first.build_tree())
    trees.append(by.build_tree())
    print("snapshot", t.append([batch_of_columns(trees^)]))
