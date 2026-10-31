<?php

/** @import-library */

namespace {
    /** Task rules and SQLite persistence, implemented with PHP PDO_SQLITE. */
    class TaskStore
    {
        private \PDO $db;
        public function __construct(string $file)
        {
        }
        public function all(): array
        {
        }
        public function find(string $id): ?array
        {
        }
        public function save(array $input): string
        {
        }
        public function advance(string $id): void
        {
        }
        public function delete(string $id): void
        {
        }
        private function seedExamples(): void
        {
        }
    }
    /** Controller: filtering, counts, selection and every mutation stay in PHP. */
    class TaskBoardApplication
    {
        private \TaskStore $store;
        private mixed $window;
        private string $filter = 'all';
        private string $search = '';
        private string $selectedId = '';
        public function __construct(\TaskStore $store)
        {
        }
        public function run(): int
        {
        }
        private function handle(array $event): void
        {
        }
        private function refresh(): void
        {
        }
    }
    function taskboard_data_path(): string
    {
    }
}
