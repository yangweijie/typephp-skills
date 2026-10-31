<?php

// expect: PASS_RUN ^int\(42\)$
// Container type annotations: Box sharing, StdArray/Map/OrderedMap, StdList/StdDict.

use \StdVector;
use \StdMap;
use \StdOrderedMap;
use \StdList;
use \StdDict;

function append(#[StdVector(Type::Int)] box $values): void
{
    $values[] = 42;
}

function setPrice(#[StdMap(Type::String, Type::Float)] $prices): void
{
    $prices['apple'] = 2.5;
}

function visit(#[StdOrderedMap(Type::Int, Type::Str)] $users): string
{
    $out = '';
    foreach ($users as $id => $user) {
        $out .= $id . '=' . $user . ';';
    }
    return $out;
}

function sumList(#[StdList(Type::Int)] array $xs): int
{
    $t = 0;
    foreach ($xs as $x) {
        $t = $t + $x;
    }
    return $t;
}

function countDict(#[StdDict(Type::Str, Type::Int)] array $m): int
{
    $t = 0;
    foreach ($m as $v) {
        $t = $t + $v;
    }
    return $t;
}

function main(): void
{
    $vals = std::vector(Type::Int);
    append($vals);
    var_dump($vals[0]);

    $prices = std::map(Type::String, Type::Float);
    setPrice($prices);
    var_dump($prices['apple']);

    $users = std::orderedMap(Type::Int, Type::Str);
    $users[1] = 'a';
    $users[2] = 'b';
    echo visit($users), "\n";

    $list = std::list(Type::Int);
    $list[] = 1;
    $list[] = 2;
    $list[100] = 3;
    echo 'list sum=', sumList($list), "\n";

    $dict = std::dict(Type::Str, Type::Int);
    $dict['a'] = 1;
    $dict['b'] = 2;
    echo 'dict sum=', countDict($dict), "\n";
}
