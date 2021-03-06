pragma solidity ^0.4.23;


contract TwoUp {

    enum CoinResult {HEADSHEADS, HEADSTAIL, TAILHEADS, TAILSTAILS}

    mapping (uint => Game) public games;
    uint constant public AVG_PRICE = 0.01 ether;

    struct Game {
        address[] heads;
        address[] tails;
        bytes32 hashedSeed;
        uint blockNumberToUse;
        address spinner;
        GameState state;
    }

    enum GameState {NEW, OPEN, CLOSED, SPINNING}

    // the app acts as the 'boxer', but does not take a cut.
    address boxer;
    address owner; //can set the boxer

    constructor() public {
        owner = msg.sender;
    }

    modifier gameOpen(uint _gameId) {
        require(games[_gameId].state == GameState.OPEN, "Game round not open");
        _;
    }

    modifier onlySpinner(uint _gameId) {
        address spinner = games[_gameId].spinner;
        require(spinner != address(0), "Spinner not selected");
        require(spinner == msg.sender, "Not the selected spinner");
        _;
    }

    modifier onlyBoxer() {
        require(msg.sender == boxer);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function setBoxer(address _boxer) public onlyOwner {
        boxer = _boxer;
    }

    // returns a game id unique to the sender+block. Used for all other functions.
    function createGame() public returns (uint _gameId) {
        _gameId = uint(keccak256(msg.sender, blockhash(block.number-1)));
        Game storage g = games[_gameId];
        require(g.state == GameState.NEW);
        g.state = GameState.OPEN;        
        return _gameId;
    }

    // place a bet on heads-heads for an open game
    function guessHeads(uint _gameId) public payable gameOpen(_gameId) {
        require(msg.value >= AVG_PRICE);
        games[_gameId].heads.push(msg.sender);
    }

    // place a bet on tails-tails for an open game
    function guessTails(uint _gameId) public payable gameOpen(_gameId) {
        require(msg.value >= AVG_PRICE);
        games[_gameId].tails.push(msg.sender);
    }

    // spinner chosen from heads addresses at random, players matched, guessing is closed.
    function pickSpinner(uint _gameId) public onlyBoxer gameOpen(_gameId) returns (address) {
        Game storage g = games[_gameId];
        address[] storage heads = g.heads;
        g.spinner = heads[uint(keccak256(blockhash(block.number-1))) % heads.length];

        // truncate unmached guesses
        if (g.heads.length > g.tails.length) {
            removePlayersFrom(g.heads, g.tails.length);
        } else if (g.tails.length > g.heads.length) {
            removePlayersFrom(g.tails, g.heads.length);
        }
        assert(g.tails.length == g.heads.length);

        g.state = GameState.CLOSED;
        return g.spinner;
    }

    // backup function in case spinner not active
    function newSpinner(uint _gameId) public onlyBoxer returns (address) {
        Game storage g = games[_gameId];
        require(g.state == GameState.CLOSED, "Game is not yet closed");
        g.state = GameState.OPEN;
        return pickSpinner(_gameId);
    }

    // Only the spinner can flip the kip (maybe relax restriction for usability)
    function flipKip(uint _gameId, bytes32 _hashedSeed) public onlySpinner(_gameId) {
        Game storage g = games[_gameId];
        require(g.state == GameState.CLOSED, "Game is not yet closed");
        g.hashedSeed = _hashedSeed;
        g.blockNumberToUse = block.number+1;
        g.state = GameState.SPINNING;
    }

    event TwoUpResult(uint gameId, uint result); //CoinResult

    // spinner only (should be called within 256 blocks)
    function reviewResults(uint _gameId, bytes32 _seed) public onlySpinner(_gameId) {
        Game storage g = games[_gameId];
        require(g.state == GameState.SPINNING);
        require(g.hashedSeed == keccak256(_seed));
        g.hashedSeed = "";

        // generate and emit result event
        bytes32 blockHash = blockhash(g.blockNumberToUse);
        uint random = uint(keccak256(uint(_seed) + uint(blockHash)));
        CoinResult result = CoinResult(random % 4);
        emit TwoUpResult(_gameId, uint(result));

        // Heads or tails, winner paid out, reset game.
        bool newGame = true;
        if (result == CoinResult.HEADSHEADS) {
            payoutWinners(g.heads);
        } else if (result == CoinResult.TAILSTAILS) {
            payoutWinners(g.tails);
        } else { // Odds, prepare for reflip of the kip
            newGame = false;
            g.state = GameState.CLOSED; //requires reflip
        }
        if (newGame) {
            g.heads.length = 0;
            g.tails.length = 0;
            g.state = GameState.OPEN;
        }
    }

    // Remove (and refund) players starting from given index
    function removePlayersFrom(address[] storage _players, uint _startIndex) internal {
        assert(_startIndex < _players.length);
        for (uint i = _startIndex; i < _players.length; i++) {
            _players[i].transfer(AVG_PRICE);
        }
        _players.length = _startIndex;
    }

    // Reward winning players
    function payoutWinners(address[] storage _winners) internal {
        for (uint i=0; i < _winners.length; i++) {
            _winners[i].transfer(AVG_PRICE*2);
        }
    }
}
