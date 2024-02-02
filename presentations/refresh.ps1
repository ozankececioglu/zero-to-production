$file = "chapter3-part2.md"
$lastWrite = gi $file | % LastWriteTime

while ($true) {
    $write = gi $file | % LastWriteTime
    if ($lastWrite -lt $write) {
        $lastWrite = $write
        pandoc -t revealjs -s -o .\chapter3-part2.html .\chapter3-part2.md -V revealjs-url=revealjs --standalone
        echo "generated"
    }
    sleep 0.1
}
