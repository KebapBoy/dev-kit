<?php

// PHP-CS-Fixer (just check, just fmt): PER coding style with 4 spaces
$finder = (new PhpCsFixer\Finder())
    ->in(__DIR__)
    ->exclude(['vendor']);

return (new PhpCsFixer\Config())
    ->setRules([
        '@PER-CS' => true,
        'declare_strict_types' => true,
    ])
    ->setRiskyAllowed(true)
    ->setFinder($finder);
