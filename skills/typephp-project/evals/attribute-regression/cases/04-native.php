<?php

// expect: PASS_RUN ^3$
// #[Native]: fixed layout, callee mutation visible, pointer assignment semantics.

use \Native;

#[Native]
class Point
{
    public int $x = 0;
    public int $y = 0;

    public function __construct(int $x, int $y)
    {
        $this->x = $x;
        $this->y = $y;
    }

    public function sum(): int
    {
        return $this->x + $this->y;
    }

    public function moveTo(int $x, int $y): void
    {
        $this->x = $x;
        $this->y = $y;
    }
}

function move(Point $p, int $x, int $y): void
{
    $p->moveTo($x, $y);
}

function main(): void
{
    $p = new Point(10, 20);
    echo $p->sum(), "\n";
    move($p, 30, 40);
    echo $p->sum(), "\n";
    $alias = $p;
    $alias->moveTo(1, 2);
    echo $p->sum(), "\n";
}
