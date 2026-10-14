"""Public landing page contract: honest source status and auth navigation."""

from html.parser import HTMLParser
from pathlib import Path


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = set()
        self.tags = set()
        self.source_cards = set()
        self.text = []

    def handle_starttag(self, tag, attrs):
        self.tags.add(tag)
        fields = dict(attrs)
        if tag == 'a':
            self.links.add(fields.get('href'))
        if fields.get('data-source'):
            self.source_cards.add(fields['data-source'])

    def handle_data(self, data):
        self.text.append(data)


def test_landing_page():
    path = Path(__file__).resolve().parents[2] / 'config' / 'home-page.html'
    assert path.exists(), 'Configured HTML landing page must exist'
    html = path.read_text(encoding='utf-8')
    parsed = Page()
    parsed.feed(html)
    content = ' '.join(parsed.text)
    assert {'/sign-in', '/sign-up', '/playground', '/models'} <= parsed.links
    assert {'gemini', 'argon', 'chaoxing', 'chatgpt'} == parsed.source_cards
    assert 'gemini-4-argon' in content
    assert '等值' in content and '非固定 token 数' in content
    assert '待验收' in content and '禁用' in content
    assert '实验 · 已验证' in content
    assert '4 Argon' in content
    assert 'chatgpt-web-gpt-5-5' in content
    assert 'Flash 模型经网关真实回答' not in content
    assert 'style' in parsed.tags and '@media' in html
    assert 'script' not in parsed.tags and 'form' not in parsed.tags
    print('PASS: responsive landing links, honest statuses and baseline-token-equivalent disclaimer')


if __name__ == '__main__':
    test_landing_page()
