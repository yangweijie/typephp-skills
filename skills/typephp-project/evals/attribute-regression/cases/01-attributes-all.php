<?php

// expect: PASS_RUN ^User\(name=rango, id=7\)$
// Printer + Arrayable + Constructor/Getter/Setter/With + Override + MustUse, all in one program.

use \Getter;
use \Setter;
use \With;
use \Constructor;
use \Printer;
use \Arrayable;
use \MustUse;
use \Override;

#[Printer(fields: ['name', 'id'])]
#[Arrayable(fields: ['id', 'name'])]
final class User
{
    #[Constructor, Getter]
    private int $id;

    #[Constructor, Getter, Setter, With]
    private string $name = '';
}

interface Fmt
{
    public function format(): string;
}

final class JsonFmt implements Fmt
{
    #[\Override]
    public function format(): string
    {
        return '{}';
    }
}

#[MustUse]
function openFile(string $f): string
{
    return $f;
}

function main(): void
{
    $u = new User(7, 'rango');
    echo $u, "\n";
    var_dump($u->toArray());
    echo $u->withName('finch')->getName(), "\n";
    echo (new JsonFmt())->format(), "\n";
    $r = openFile('a.txt');
    echo $r, "\n";
}
