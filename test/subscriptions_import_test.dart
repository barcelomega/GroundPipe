import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/data/repository/ng_repository.dart';

const _followingPage = '''
<div class="grid-max5">
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://pixiekid66.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/10750/10750935_medium.webp" alt="pixiekid66's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://pixiekid66.newgrounds.com">pixiekid66</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://p1an1st-mak3s-mus1c.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/26095/26095476_medium.webp" alt="p1an1st-mak3s-mus1c's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://p1an1st-mak3s-mus1c.newgrounds.com">p1an1st-mak3s-mus1c</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://lemkuuja.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/4937/4937096_medium.webp" alt="LemKuuja's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://lemkuuja.newgrounds.com">LemKuuja</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://calamityrhapsody.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/27072/27072542_medium.webp" alt="CalamityRhapsody's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://calamityrhapsody.newgrounds.com">CalamityRhapsody</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://jam-power.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/10787/10787959_medium.webp" alt="JAM-POWER's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://jam-power.newgrounds.com">JAM-POWER</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://piocky.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/9915/9915512_medium.webp" alt="pIocky's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://piocky.newgrounds.com">pIocky</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://lumpytouch.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/7071/7071694_medium.webp" alt="LumpyTouch's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://lumpytouch.newgrounds.com">LumpyTouch</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://zanelittle.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/4788/4788856_medium.webp" alt="ZaneLittle's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://zanelittle.newgrounds.com">ZaneLittle</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://gdwerx7499.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/22651/22651926_medium.webp" alt="GDWerx7499's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://gdwerx7499.newgrounds.com">GDWerx7499</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://f4t4lfrankie.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/22141/22141183_medium.webp" alt="f4t4lfrankie's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://f4t4lfrankie.newgrounds.com">f4t4lfrankie</a></h4>
      </div>
    </div></span>
  </div>
  <div class="span-1">
    <span><div class="item-user-small">
      <div class="item-icon">
        <a href="https://dx7fm.newgrounds.com"><img class="user-icon" src="https://uimg.ngfiles.com/icons/26907/26907839_medium.webp" alt="DX7FM's icon" /></a>
      </div>
      <div class="item-details">
        <h4><a href="https://dx7fm.newgrounds.com">DX7FM</a></h4>
      </div>
    </div></span>
  </div>
</div>
''';

void main() {
  final repo = NgRepository();

  test('following page parses user cards and names', () {
    final (authors, next) = repo.parseFollowingPage(_followingPage);

    expect(authors, hasLength(11));
    expect(authors.first.username, 'pixiekid66');
    expect(authors.first.name, 'pixiekid66');
    expect(authors.first.subscribed, isTrue);
    expect(authors.map((author) => author.username), contains('lemkuuja'));
    expect(authors.last.username, 'dx7fm');
    expect(authors.last.name, 'DX7FM');
    expect(next, isNull);
  });

  test('following page finds the AJAX next-page URL', () {
    const html = r'''
<div class="item-user-small">
  <div class="item-details"><h4><a href="https://pixiekid66.newgrounds.com">pixiekid66</a></h4></div>
</div>
<script>
  UsersFollowingController.loadMore($('#load-more'), "https:\/\/hoongtube.newgrounds.com\/favorites\/following?page=2", "div", ".grid-max5", "following").watch();
</script>
''';

    final (authors, next) = repo.parseFollowingPage(html);

    expect(authors, hasLength(1));
    expect(next, 'https://hoongtube.newgrounds.com/favorites/following?page=2');
  });

  test('following page deduplicates users and ignores site links', () {
    const html = '''
<div class="item-user-small">
  <div class="item-details"><h4><a href="https://pixiekid66.newgrounds.com">pixiekid66</a></h4></div>
</div>
<div class="item-user-small">
  <div class="item-details"><h4><a href="https://pixiekid66.newgrounds.com/">pixiekid66</a></h4></div>
</div>
<div class="item-user-small">
  <div class="item-details"><h4><a href="https://www.newgrounds.com">Newgrounds</a></h4></div>
</div>
''';

    final (authors, _) = repo.parseFollowingPage(html);

    expect(authors, hasLength(1));
    expect(authors.single.username, 'pixiekid66');
  });
}
