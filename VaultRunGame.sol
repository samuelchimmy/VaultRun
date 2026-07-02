// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VaultRunGame
 * @notice Transparent game economy contract for VaultRun.
 * @dev Players enter daily challenge by depositing stablecoins.
 *      Top 3 scorers split 80% of daily pool. Dev gets 20%.
 *      All pool balances and scores are publicly readable.
 *      Anyone can verify payouts onchain.
 */

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract VaultRunGame {
    address public owner;
    address public devWallet;

    // Supported tokens
    address public constant USDm = 0x4F604735c1cF31399C6E711D5962b2B3E0225AD3;
    address public constant USDT  = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;
    address public constant USDC  = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;

    uint256 public constant ENTRY_FEE = 0.05e6;   // 0.05 USD (6 decimals)
    uint256 public constant DEV_RAKE  = 20;        // 20%
    uint256 public constant POOL_SHARE = 80;       // 80% to winners

    // Daily state — keyed by UTC day (block.timestamp / 86400)
    struct DayData {
        uint256 totalPool;                         // total deposited this day
        address[] players;                         // all entrants
        mapping(address => uint256) scores;        // player => best score (0–10000, basis points)
        mapping(address => bool) entered;          // dedup
        mapping(address => address) tokenUsed;     // player => token they paid with
        bool resolved;
        address[3] winners;
        uint256[3] payouts;
    }

    mapping(uint256 => DayData) private days;
    // Ghost race prize pool per token
    mapping(address => uint256) public ghostPool;

    event PlayerEntered(uint256 day, address player, address token, uint256 fee);
    event ScoreSubmitted(uint256 day, address player, uint256 score);
    event DayResolved(uint256 day, address[3] winners, uint256[3] payouts);
    event WinningsClaimed(address player, uint256 amount, address token);
    event GhostRaceResult(address player, bool won, uint256 payout);

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor(address _devWallet) {
        owner = msg.sender;
        devWallet = _devWallet;
    }

    /// @notice Returns current UTC day
    function currentDay() public view returns (uint256) {
        return block.timestamp / 86400;
    }

    /// @notice Enter the daily challenge. Player must approve token first.
    function enterDailyChallenge(address token) external {
        require(token == USDm || token == USDT || token == USDC, "Token not supported");
        uint256 day = currentDay();
        DayData storage d = days[day];
        require(!d.entered[msg.sender], "Already entered today");
        require(!d.resolved, "Day already resolved");

        IERC20(token).transferFrom(msg.sender, address(this), ENTRY_FEE);

        d.players.push(msg.sender);
        d.entered[msg.sender] = true;
        d.tokenUsed[msg.sender] = token;
        d.totalPool += ENTRY_FEE;

        emit PlayerEntered(day, msg.sender, token, ENTRY_FEE);
    }

    /// @notice Submit score after run. Score in basis points (10000 = 100%).
    function submitScore(uint256 score) external {
        require(score <= 10000, "Invalid score");
        uint256 day = currentDay();
        DayData storage d = days[day];
        require(d.entered[msg.sender], "Not entered");
        require(!d.resolved, "Day resolved");
        // Keep best score only
        if (score > d.scores[msg.sender]) {
            d.scores[msg.sender] = score;
            emit ScoreSubmitted(day, msg.sender, score);
        }
    }

    /// @notice Resolve a completed day. Callable by owner after 23:59 UTC.
    /// @dev Finds top 3 players, splits pool 80% proportionally, sends 20% to dev.
    function resolveDay(uint256 day) external onlyOwner {
        DayData storage d = days[day];
        require(!d.resolved, "Already resolved");
        require(day < currentDay(), "Day not over");

        d.resolved = true;

        uint256 n = d.players.length;
        if (n == 0) return;

        // Find top 3 (simple sort over potentially small array — gas acceptable for daily call)
        address[3] memory top;
        uint256[3] memory topScores;
        for (uint256 i = 0; i < n; i++) {
            address p = d.players[i];
            uint256 s = d.scores[p];
            if (s > topScores[0]) { topScores[2]=topScores[1]; top[2]=top[1]; topScores[1]=topScores[0]; top[1]=top[0]; topScores[0]=s; top[0]=p; }
            else if (s > topScores[1]) { topScores[2]=topScores[1]; top[2]=top[1]; topScores[1]=s; top[1]=p; }
            else if (s > topScores[2]) { topScores[2]=s; top[2]=p; }
        }

        // Prize pool = 80% of total
        uint256 prizePool = (d.totalPool * POOL_SHARE) / 100;
        uint256 totalScore = topScores[0] + topScores[1] + topScores[2];

        uint256[3] memory payouts;
        if (totalScore > 0) {
            for (uint8 i = 0; i < 3; i++) {
                if (top[i] != address(0)) {
                    payouts[i] = (prizePool * topScores[i]) / totalScore;
                }
            }
        }

        // Use USDm as settlement token for prize pool (contract holds mixed tokens — simplification:
        // in production use a DEX or per-token pools; for MVP, collect in one token per day)
        // Transfer payouts
        address settleToken = d.tokenUsed[top[0]] != address(0) ? d.tokenUsed[top[0]] : USDm;
        for (uint8 i = 0; i < 3; i++) {
            if (top[i] != address(0) && payouts[i] > 0) {
                IERC20(settleToken).transfer(top[i], payouts[i]);
            }
        }

        // Dev rake
        uint256 devCut = (d.totalPool * DEV_RAKE) / 100;
        IERC20(settleToken).transfer(devWallet, devCut);

        d.winners = top;
        d.payouts = payouts;

        emit DayResolved(day, top, payouts);
    }

    /// @notice Enter ghost race — win 1.8x entry if you beat today's top score
    function enterGhostRace(address token) external {
        require(token == USDm || token == USDT || token == USDC, "Token not supported");
        IERC20(token).transferFrom(msg.sender, address(this), ENTRY_FEE);
        ghostPool[token] += ENTRY_FEE;
        emit PlayerEntered(currentDay(), msg.sender, token, ENTRY_FEE);
    }

    /// @notice Called by backend/owner after ghost race result is verified offchain
    function resolveGhostRace(address player, bool won, address token) external onlyOwner {
        if (won) {
            uint256 payout = (ENTRY_FEE * 18) / 10; // 1.8x
            require(ghostPool[token] >= payout, "Pool too small");
            ghostPool[token] -= payout;
            IERC20(token).transfer(player, payout);
            emit GhostRaceResult(player, true, payout);
        } else {
            emit GhostRaceResult(player, false, 0);
        }
    }

    // ── View functions (fully transparent) ──────────────────────────────────

    function getDayPool(uint256 day) external view returns (uint256) {
        return days[day].totalPool;
    }

    function getDayPlayerCount(uint256 day) external view returns (uint256) {
        return days[day].players.length;
    }

    function getPlayerScore(uint256 day, address player) external view returns (uint256) {
        return days[day].scores[player];
    }

    function isDayResolved(uint256 day) external view returns (bool) {
        return days[day].resolved;
    }

    function getDayWinners(uint256 day) external view returns (address[3] memory, uint256[3] memory) {
        return (days[day].winners, days[day].payouts);
    }

    function updateDevWallet(address newWallet) external onlyOwner {
        devWallet = newWallet;
    }
}
