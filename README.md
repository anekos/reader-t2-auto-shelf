## ᛊᛟᛅy ᚱᛖᚫᛞᛖᚱ

reader-t2 にファイルを転送し、ついでに本棚を自動生成します。


## 使いかた

以下のように引数を4つ与えます。

     reader-t2-auto-shelf.rb \
       /mnt/reader-t2/body \
       /mnt/reader-t2/sd \
       /media/data/device/reader-t2/body \
       /media/data/device/reader-t2/sd

各引数の意味は下の通りです

1. reader-t2 の本体ストレージのパス
2. reader-t2 のSDストレージのパス
3. 本体へ転送したいファイルのあるディレクトリ
4. SD へ転送したいファイルのあるディレクトリ


これで、ファイルが転送され、本棚情報が書きこまれます。


## ディレクトリ形式

引数の後半二つのディレクトリは、以下のように
<本棚名>/ファイル のように一つだけディレクトリを作ってそこへ入れます。


    /media/data/device/reader-t2/sd
      ├── vimpr
      │   ├── [anekos] Happy Hacking Vimperator.epub
      │   └── [anekos616] 獄門 Vimperator.epub
      ├── vim
      │   ├── [しょうご] 小学生ではわからないかもしれない Vim.epub
      │   └── [まんぼう] 水銀.epub
      └── xmonad
          ├── [えっきすもな堂] えっきすモナ道.epub
          └── [anekos] おれおれ conf.epub

この場合、 vimpr vim xmonad の三つの本棚ができて、
それぞれに本が入ります。

## 備考

転送されるファイルのファイル名に日本語などが使われる場合は、
Base64 っぽいリネームが行なわれます。
もちろん、転送元のファイルはリネームされません。

## Requirements

Ruby1.9
sqlite3-ruby
term-ansicolor
