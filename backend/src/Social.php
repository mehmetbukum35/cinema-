<?php
declare(strict_types=1);
// Sosyal ağ, arkadaşlık, zevk uyumu ve ortak izleme listesi kesişimi iş mantığı.

require_once __DIR__ . '/Social/SupportTrait.php';
require_once __DIR__ . '/Social/DevicesTrait.php';
require_once __DIR__ . '/Social/ProfilesTrait.php';
require_once __DIR__ . '/Social/FriendsTrait.php';
require_once __DIR__ . '/Social/FeedTrait.php';
require_once __DIR__ . '/Social/MatchTrait.php';
require_once __DIR__ . '/Social/RecommendationsTrait.php';
require_once __DIR__ . '/Social/ReviewsTrait.php';
require_once __DIR__ . '/Social/ProfilesPublicTrait.php';
require_once __DIR__ . '/Social/TitlesPublicTrait.php';
require_once __DIR__ . '/Social/CouchTrait.php';

class Social
{
    use SocialSupportTrait;
    use SocialDevicesTrait;
    use SocialProfilesTrait;
    use SocialFriendsTrait;
    use SocialFeedTrait;
    use SocialMatchTrait;
    use SocialRecommendationsTrait;
    use SocialReviewsTrait;
    use SocialProfilesPublicTrait;
    use SocialTitlesPublicTrait;
    use SocialCouchTrait;

    public function __construct(
        private PDO $db,
        private ?SocialWebRenderer $webRenderer = null,
        private ?Fcm $fcm = null
    ) {}

    public function webRenderer(): SocialWebRenderer
    {
        return $this->webRenderer ??= new SocialWebRenderer($this->db);
    }
}
