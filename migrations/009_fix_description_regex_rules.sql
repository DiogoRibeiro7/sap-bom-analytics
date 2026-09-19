BEGIN;

UPDATE classification.rule
SET pattern = '(^|[^[:alnum:]_])bottle([^[:alnum:]_]|$)',
    classifier_version = 'rules-0.1.1'
WHERE rule_name = 'description-bottle-plastic';

UPDATE classification.rule
SET pattern = '(^|[^[:alnum:]_])(closure|cap)([^[:alnum:]_]|$)',
    classifier_version = 'rules-0.1.1'
WHERE rule_name = 'description-closure-plastic';

COMMIT;
