from app.core.security import new_token, token_hash


def test_new_token_is_url_safe_and_reasonably_long():
    token = new_token()
    assert len(token) >= 32
    assert all(char.isalnum() or char in "-_" for char in token)


def test_new_token_is_not_predictable_across_calls():
    tokens = {new_token() for _ in range(20)}
    assert len(tokens) == 20


def test_token_hash_is_deterministic_for_the_same_input():
    token = new_token()
    assert token_hash(token) == token_hash(token)


def test_token_hash_differs_for_different_tokens():
    assert token_hash(new_token()) != token_hash(new_token())


def test_token_hash_never_reveals_the_raw_token():
    token = new_token()
    assert token not in token_hash(token)


def test_token_hash_is_a_fixed_length_hex_digest():
    digest = token_hash(new_token())
    assert len(digest) == 64
    assert all(char in "0123456789abcdef" for char in digest)
