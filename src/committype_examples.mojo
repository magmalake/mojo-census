"""The hand-labelled commits `committype` types the rest by (#121): 100
commits from 58 census repos that the subject rules call `other`, each
labelled from its diff (main type, then secondary types) and checked by
hand. Each is `<main>|<secondary,...>|<FileMix.encode of its files>`, with
the commit it is in a comment. A new label or example is a new
`COMMIT_TYPES_VERSION`."""


def commit_examples() -> List[String]:
    return [
        "feature|test,fix|1 0 0 76 4 0 0 0 0 52 4 1 75 5",  # tamnd/firepanda@18ea59dc32
        "migration||1 204 0 0 0 0 0 0 0 0 6 0 102 102",  # mzaks/compact-dict@7f0b93a71a
        "fix||1 5 6 0 0 0 0 0 0 6 2 0 11 0",  # magmalake/objectstore.mojo@93cc6257aa
        "feature||1 115 0 0 0 0 0 0 0 0 1 0 71 44",  # Terapines/llm.mojo@b0865b5796
        "feature||1 37 0 0 0 0 0 0 0 0 1 0 36 1",  # krjadhav/mojo_gpu_puzzles@3371c48cd6
        "refactor||1 0 0 0 0 20 516 0 3874 0 22 11 2205 2205",  # degiwo/old-projects@35b07a020b
        "docs||1 0 0 0 188 0 0 0 0 0 1 0 100 88",  # msaelices/mojo-regex@5d45d3d2ed
        "migration||1 15 0 0 0 0 177 0 0 0 3 0 96 96",  # carlca/ca_mojo@2feb5c334e
        "refactor||1 0 0 169 0 135 0 0 0 0 7 0 0 304",  # degiwo/old-projects@53ab4c0467
        "chore|test,docs|1 5 62 38 47 6 0 0 0 100 12 0 118 40",  # nsalerni/grpc-mojo@7157ad14d8
        "fix|test,chore|1 745 492 0 0 0 0 0 0 492 6 2 399 838",  # MoSafi2/cairo-mojo@eee99b0d93
        "feature||1 20 0 0 0 0 0 0 0 0 1 0 9 11",  # enriquegomeztagle/mojo@588f148ec4
        "docs||1 0 0 0 14 0 0 0 0 0 1 0 14 0",  # tamnd/firepanda@d622ab4332
        "refactor||1 8 0 0 0 0 0 0 0 0 2 0 5 3",  # avitkauskas/mojo-datastructs@731fb1b524
        "refactor||1 344 8 0 0 0 0 0 2 8 7 0 162 192",  # CoffeeVampir3/Mojo-Linuxperiments@a61488fdab
        "refactor||1 2 386 0 0 0 0 0 0 386 4 2 194 194",  # MoSafi2/cairo-mojo@f6b6f54a54
        "docs||1 0 0 0 126 0 0 0 0 0 2 1 123 3",  # lee101/mojo-imagehash@d4b83915df
        "feature|test|1 0 0 274 0 0 0 0 0 108 5 3 265 9",  # mhoffma/llm_mojo@2bad86d352
        "refactor||1 24 0 0 0 0 0 0 0 0 1 0 8 16",  # rd4com/ui-terminal-mojo@bbe0b88a6e
        "feature||1 171 0 0 0 0 0 0 0 0 3 1 169 2",  # joelflaig/NexusNet@a6c4e600be
        "fix|test|1 9 144 25 22 0 0 0 30 169 5 0 228 2",  # magmalake/objectstore.mojo@6da4bbad2e
        "fix|test,docs|1 239 476 0 27 0 0 0 0 476 10 0 661 81",  # nsalerni/grpc-mojo@ba031b3be1
        "chore||1 3 0 0 0 12 1343 0 0 0 6 0 1351 7",  # millfolio/lancedb.mojo@ed825419eb
        "refactor|chore|1 805 834 0 0 0 0 0 0 834 6 4 820 819",  # avitkauskas/mojo-datastructs@d7f63cc4f8
        "chore||1 0 0 2 263 7 0 15 0 0 122 1 148 139",  # ethqnol/strata-mojo@c71beb6fe9
        "refactor|feature|1 637 0 0 0 0 0 0 0 0 10 1 340 297",  # joelflaig/NexusNet@085acf22a0
        "migration||1 5 0 0 0 0 417 0 0 0 2 0 279 143",  # carlca/ca_mojo@b662e0034a
        "refactor||1 30 0 0 0 0 0 0 0 0 1 0 19 11",  # sergey-sonkin/adventofmojo2024@40004dff81
        "perf|fix,docs|1 3581 30 0 325 0 0 0 1 30 43 28 3784 153",  # oliveagle/tokenizers_mojo@20238ab509
        "docs||1 0 0 0 2 0 0 0 0 0 1 0 1 1",  # guidorice/mogeo@90b95f5866
        "feature|docs|1 167 151 0 17 0 0 0 0 151 8 2 271 64",  # TilliFe/Infermo@a1aee21b25
        "chore||1 0 0 0 0 1 0 0 0 0 1 0 1 0",  # enriquegomeztagle/mojo@ec5ce2c21a
        "feature|test,chore|1 0 0 108 5 8 0 4 0 56 8 2 121 4",  # nsalerni/mojo-http2@48dfdee603
        "refactor|perf|1 194 159 0 0 0 0 0 0 159 12 3 229 124",  # CoffeeVampir3/Mojo-Linuxperiments@35bfb9604f
        "feature|test,docs|1 95 0 1843 133 5 0 0 364 889 34 27 2430 10",  # atveit/mojopi@cb1e73ec23
        "fix||1 85 0 0 0 0 0 0 0 0 1 0 43 42",  # Terapines/llm.mojo@986e384a93
        "fix|feature|1 195 0 0 2 0 0 0 0 0 5 1 107 90",  # TilliFe/Infermo@84af518f69
        "chore||1 0 0 0 0 0 0 29 0 0 1 1 29 0",  # seanpm2001/AI2001_Category-Source_Code-SC-Mojo@6fb574b62a
        "chore||1 0 0 0 0 0 0 0 196 0 1 1 196 0",  # seanpm2001/AI2001_Category-Source_Code-SC-Mojo@07ea234a27
        "test||1 0 205 90 0 10 0 0 0 295 11 2 167 138",  # guidorice/mogeo@6a9a60c8ba
        "feature|test,perf|1 326 65 0 0 0 0 0 0 65 3 3 391 0",  # oliveagle/tokenizers_mojo@229144bdaf
        "feature||1 153 0 0 0 0 0 0 0 0 1 1 153 0",  # sergey-sonkin/adventofmojo2024@fdd535e89e
        "perf||1 1752 0 1704 90 1179 0 0 0 0 17 16 4725 0",  # ethqnol/strata-mojo@4b1c043462
        "feature||1 2 0 0 0 0 0 0 0 0 1 0 1 1",  # johnsoez4/pendulum@e847398566
        "chore||1 0 0 0 0 0 0 0 2 0 1 0 1 1",  # johnsoez4/pendulum@e727362310
        "docs||1 0 0 0 38 0 0 0 0 0 1 0 21 17",  # conorbronsdon/mojo-redis@bdf106fb7a
        "test|fix|1 0 0 611 0 0 0 0 0 567 4 0 601 10",  # lee101/mojo-biopython@1a53dfc2ed
        "refactor|feature,docs|1 699 0 0 0 0 0 0 0 0 7 0 513 186",  # Mojo-Numerics-and-Algorithms-group/NuMojo@1488253145
        "docs||1 0 0 0 77 0 0 0 0 0 2 1 58 19",  # minhtran241/mojo-playground@befe9d1ce2
        "docs||1 0 0 0 227 0 0 0 0 0 1 0 109 118",  # Spellbound-Mojo/fp_mojo@162891ff8a
        "refactor|feature,chore|1 4520 37 0 0 1 0 26 7 37 22 0 527 4064",  # Mojo-Numerics-and-Algorithms-group/NuMojo@626ef94974
        "chore||1 0 0 0 0 1 0 0 0 0 1 0 1 0",  # mhoffma/llm_mojo@564cffb6f3
        "feature|test,docs|1 64 0 2150 578 0 0 0 0 1173 22 19 2791 1",  # atveit/mojopi@596f0eaa70
        "chore||1 0 0 0 0 8 0 0 0 0 2 0 5 3",  # millfolio/lancedb.mojo@f82aff757b
        "perf||1 49 0 0 0 0 0 0 0 0 1 0 44 5",  # mzaks/compact-dict@33784efd45
        "refactor||1 272 0 0 0 0 0 0 0 0 1 0 54 218",  # msaelices/mojo-regex@ec801f83bc
        "perf|docs|1 0 0 0 30 0 0 0 226 0 3 0 225 31",  # IAFahim/mojo-blender-cube@b1a36ecd0e
        "refactor||1 13 0 0 0 0 0 0 0 0 1 0 9 4",  # rd4com/ui-terminal-mojo@dcfc5eafd9
        "feature|docs|1 191 0 0 61 0 0 0 51 0 9 9 303 0",  # dbusteed/mojolings@6b8abfa65b
        "test||1 0 0 238 0 2 0 0 0 101 3 1 221 19",  # nsalerni/mojo-http2@5d27260183
        "docs||1 0 0 0 1297 0 0 0 0 0 28 0 874 423",  # Spellbound-Mojo/fp_mojo@60fc0b965a
        "chore||1 0 0 0 11 0 0 0 0 0 1 0 5 6",  # tyukei/mojo-streamlit@fc7754af1a
        "chore||1 0 0 0 0 4 0 0 0 0 2 0 2 2",  # minhtran241/mojo-playground@815c2217a0
        "refactor|other|1 24 0 26 0 0 0 0 0 0 6 3 25 25",  # flow-state-15/Mojo-intro@e14403973b
        "docs||1 0 0 0 6 0 0 0 0 0 3 0 3 3",  # murtazox04/mojogram@b4a6a450ee
        "chore|docs|1 0 7 0 51 10 0 51 134 7 12 2 215 38",  # Ameyanagi/yomi@f5a0743c48
        "migration||1 0 0 0 0 23 0 0 0 0 1 0 8 15",  # modular/mojo-syntax@46eccdaeda
        "docs||1 0 0 0 4 0 0 0 0 0 1 1 4 0",  # dongsub-joung/for-die-NOT-Facked-K-Pop-trainee@8abb12cd0f
        "feature||1 1532 91 0 1 0 0 0 0 91 36 36 1624 0",  # nadineMck/mojo-project@b90a4001e1
        "chore||1 0 0 0 0 0 0 0 0 0 1 0 0 0",  # spluta/Interop_Test@f31cd8dde3
        "chore|fix,docs|1 0 0 0 11 9 0 0 0 0 2 0 14 6",  # IAFahim/mojo-blender-cube@8b3a32fc9a
        "fix|test|1 0 0 777 3 0 0 0 0 584 4 1 747 33",  # lee101/mojo-anndata@4fe6c1aa12
        "feature|refactor|1 528 0 0 0 0 0 0 8 0 21 14 423 113",  # dbusteed/mojolings@b879e2cac6
        "perf|docs|1 0 0 55 48 0 0 0 0 0 2 0 73 30",  # lee101/mojo-anndata@a55a04c498
        "docs||1 0 0 0 38 0 0 0 0 0 1 0 21 17",  # conorbronsdon/mojo-tar@4309ebfd3e
        "version|chore|1 0 0 0 0 0 0 69 0 0 2 0 63 6",  # conorbronsdon/mojo-redis@da0c079e97
        "refactor||1 0 0 0 0 0 0 0 0 0 2 1 0 0",  # codenetwork/mojomagic@a387c0bc92
        "docs||1 0 0 0 264 0 0 0 0 0 2 1 224 40",  # lee101/mojo-imagehash@f85bc61024
        "docs||1 0 0 0 94 0 0 0 0 0 1 1 94 0",  # lee101/mojo-genesis-world@dcea6808b5
        "docs||1 0 0 0 9 0 0 0 0 0 1 0 5 4",  # rd4com/mojo-magiclist@54eee6d577
        "feature|chore|1 652 0 0 45 0 0 0 0 0 3 3 697 0",  # winding-lines/kd_tree.mojo@e265cf446e
        "fix|chore|1 63 0 0 0 2 0 0 0 0 2 0 29 36",  # RuthvikMukkamala/mojo-pinns@99afbf9910
        "fix||1 0 0 2 0 0 0 0 0 0 1 0 1 1",  # RameshBabuAsh/FriDAY-AI@ca32aa8918
        "feature|docs,chore|1 14 0 62 1 0 0 0 0 0 4 1 9 68",  # RuthvikMukkamala/mojo-pinns@54441623f2
        "migration||1 0 0 0 0 2 0 0 0 0 1 0 1 1",  # modular/mojo-syntax@b351eb5c75
        "docs||1 1 0 0 0 0 0 0 0 0 1 0 0 1",  # RameshBabuAsh/FriDAY-AI@ec92178032
        "docs||1 0 0 0 55 0 0 0 0 0 1 0 43 12",  # lee101/mojo-genesis-world@1a28d23af3
        "test|fix|1 0 0 742 0 0 0 0 0 719 2 0 740 2",  # lee101/mojo-crcmod@e441e02001
        "chore||1 0 0 0 0 0 0 6 0 0 2 0 3 3",  # Ameyanagi/yomi@de01f998ea
        "docs||1 0 0 0 11 0 0 0 0 0 1 0 9 2",  # rurumimic/mojo@d0e0834419
        "perf|feature|1 317 0 0 0 0 0 0 0 0 3 1 254 63",  # SuperRiley64/MojoGameOfLife@4eb510d4b6
        "feature||1 0 0 110 0 0 0 0 0 0 2 1 109 1",  # tyukei/mojo-streamlit@201285916d
        "chore||1 0 0 0 0 6 0 0 0 0 1 1 6 0",  # millfolio/zlib.mojo@eeff2d4bbd
        "migration|refactor|1 114 0 0 0 0 0 0 0 0 1 0 96 18",  # winding-lines/kd_tree.mojo@d24aca3984
        "chore||1 0 0 0 0 8 1716 0 0 0 3 0 1720 4",  # millfolio/zlib.mojo@f243ffab8d
        "chore||1 22 0 0 0 0 0 0 0 0 1 0 1 21",  # krjadhav/mojo_gpu_puzzles@54306c0a8e
        "feature|chore,docs|1 1329 0 455 135 25 5511 0 0 0 142 142 7455 0",  # Aaditya18SP/Neophyte-cmp_mojo_and_python_yolo@37bcc68d13
        "other||1 5 0 0 0 0 0 0 0 0 1 0 5 0",  # rd4com/mojo-magiclist@bee910568f
        "version|chore|1 0 0 0 0 0 0 69 0 0 2 0 63 6",  # conorbronsdon/mojo-tar@ff0329f685
        "feature||1 3 0 0 0 0 0 0 0 0 1 1 3 0",  # truthfulle/getting-started-with-mojo@b06b5feedb
    ]
