
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Skill-Based Betting Platform
 * @dev A smart contract for managing skill-based games and betting
 * Players can create games, join games, and resolve outcomes based on skill rather than pure chance
 */
contract Project {
    
    // Struct to represent a game
    struct Game {
        uint256 gameId;
        address creator;
        address opponent;
        uint256 betAmount;
        uint256 gameType; // 1: Chess, 2: Poker, 3: Trivia, etc.
        GameStatus status;
        address winner;
        uint256 createdAt;
        uint256 timeLimit; // Time limit in seconds
        bool fundsDeposited;
        mapping(address => bool) hasDeposited;
    }
    
    enum GameStatus { 
        WAITING_FOR_OPPONENT, 
        IN_PROGRESS, 
        COMPLETED, 
        CANCELLED,
        DISPUTED
    }
    
    // State variables
    mapping(uint256 => Game) public games;
    mapping(address => uint256[]) public playerGames;
    mapping(address => uint256) public playerStats; // Win count
    
    uint256 public nextGameId = 1;
    uint256 public platformFee = 50; // 5% fee (50/1000)
    address public owner;
    uint256 public totalGamesCreated;
    
    // Events
    event GameCreated(uint256 indexed gameId, address indexed creator, uint256 betAmount, uint256 gameType);
    event GameJoined(uint256 indexed gameId, address indexed opponent);
    event GameCompleted(uint256 indexed gameId, address indexed winner, uint256 prize);
    event GameCancelled(uint256 indexed gameId);
    event FundsWithdrawn(address indexed player, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier gameExists(uint256 _gameId) {
        require(_gameId < nextGameId && _gameId > 0, "Game does not exist");
        _;
    }
    
    modifier onlyGameParticipants(uint256 _gameId) {
        require(
            msg.sender == games[_gameId].creator || 
            msg.sender == games[_gameId].opponent,
            "Only game participants can call this function"
        );
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Core Function 1: Create a new skill-based game
     * @param _gameType Type of game (1: Chess, 2: Poker, 3: Trivia, etc.)
     * @param _timeLimit Time limit for the game in seconds
     */
    function createGame(uint256 _gameType, uint256 _timeLimit) external payable {
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(_gameType >= 1 && _gameType <= 5, "Invalid game type");
        require(_timeLimit >= 300, "Time limit must be at least 5 minutes");
        
        uint256 gameId = nextGameId++;
        
        Game storage newGame = games[gameId];
        newGame.gameId = gameId;
        newGame.creator = msg.sender;
        newGame.betAmount = msg.value;
        newGame.gameType = _gameType;
        newGame.status = GameStatus.WAITING_FOR_OPPONENT;
        newGame.createdAt = block.timestamp;
        newGame.timeLimit = _timeLimit;
        newGame.fundsDeposited = true;
        newGame.hasDeposited[msg.sender] = true;
        
        playerGames[msg.sender].push(gameId);
        totalGamesCreated++;
        
        emit GameCreated(gameId, msg.sender, msg.value, _gameType);
    }
    
    /**
     * @dev Core Function 2: Join an existing game
     * @param _gameId ID of the game to join
     */
    function joinGame(uint256 _gameId) external payable gameExists(_gameId) {
        Game storage game = games[_gameId];
        
        require(game.status == GameStatus.WAITING_FOR_OPPONENT, "Game is not available to join");
        require(msg.sender != game.creator, "Cannot join your own game");
        require(msg.value == game.betAmount, "Must match the bet amount");
        require(block.timestamp <= game.createdAt + game.timeLimit, "Game has expired");
        
        game.opponent = msg.sender;
        game.status = GameStatus.IN_PROGRESS;
        game.hasDeposited[msg.sender] = true;
        
        playerGames[msg.sender].push(_gameId);
        
        emit GameJoined(_gameId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Resolve game outcome and distribute winnings
     * @param _gameId ID of the game to resolve
     * @param _winner Address of the winner
     */
    function resolveGame(uint256 _gameId, address _winner) external gameExists(_gameId) onlyGameParticipants(_gameId) {
        Game storage game = games[_gameId];
        
        require(game.status == GameStatus.IN_PROGRESS, "Game is not in progress");
        require(_winner == game.creator || _winner == game.opponent, "Winner must be one of the participants");
        require(game.hasDeposited[game.creator] && game.hasDeposited[game.opponent], "Both players must have deposited funds");
        
        game.winner = _winner;
        game.status = GameStatus.COMPLETED;
        
        // Calculate prize and platform fee
        uint256 totalPrize = game.betAmount * 2;
        uint256 fee = (totalPrize * platformFee) / 1000;
        uint256 winnerPrize = totalPrize - fee;
        
        // Update winner's stats
        playerStats[_winner]++;
        
        // Transfer winnings to winner
        payable(_winner).transfer(winnerPrize);
        
        // Transfer fee to platform owner
        payable(owner).transfer(fee);
        
        emit GameCompleted(_gameId, _winner, winnerPrize);
    }
    
    /**
     * @dev Cancel a game that hasn't started yet
     * @param _gameId ID of the game to cancel
     */
    function cancelGame(uint256 _gameId) external gameExists(_gameId) {
        Game storage game = games[_gameId];
        
        require(msg.sender == game.creator, "Only game creator can cancel");
        require(game.status == GameStatus.WAITING_FOR_OPPONENT, "Can only cancel games waiting for opponent");
        
        game.status = GameStatus.CANCELLED;
        
        // Refund the creator's bet
        payable(game.creator).transfer(game.betAmount);
        
        emit GameCancelled(_gameId);
    }
    
    /**
     * @dev Get game details
     * @param _gameId ID of the game
     */
    function getGameDetails(uint256 _gameId) external view gameExists(_gameId) returns (
        address creator,
        address opponent,
        uint256 betAmount,
        uint256 gameType,
        GameStatus status,
        address winner,
        uint256 createdAt,
        uint256 timeLimit
    ) {
        Game storage game = games[_gameId];
        return (
            game.creator,
            game.opponent,
            game.betAmount,
            game.gameType,
            game.status,
            game.winner,
            game.createdAt,
            game.timeLimit
        );
    }
    
    /**
     * @dev Get player's game history
     * @param _player Address of the player
     */
    function getPlayerGames(address _player) external view returns (uint256[] memory) {
        return playerGames[_player];
    }
    
    /**
     * @dev Get player's win count
     * @param _player Address of the player
     */
    function getPlayerStats(address _player) external view returns (uint256) {
        return playerStats[_player];
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFee New fee percentage (in basis points, e.g., 50 = 5%)
     */
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 100, "Fee cannot exceed 10%");
        platformFee = _newFee;
    }
    
    /**
     * @dev Get contract statistics
     */
    function getContractStats() external view returns (
        uint256 totalGames,
        uint256 activeGames,
        uint256 totalVolume
    ) {
        uint256 activeCount = 0;
        uint256 volume = 0;
        
        for (uint256 i = 1; i < nextGameId; i++) {
            if (games[i].status == GameStatus.WAITING_FOR_OPPONENT || games[i].status == GameStatus.IN_PROGRESS) {
                activeCount++;
            }
            volume += games[i].betAmount;
        }
        
        return (totalGamesCreated, activeCount, volume);
    }
    
    /**
     * @dev Emergency function to handle disputed games (only owner)
     * @param _gameId ID of the disputed game
     * @param _refundBoth Whether to refund both players or resolve normally
     */
    function handleDispute(uint256 _gameId, bool _refundBoth) external onlyOwner gameExists(_gameId) {
        Game storage game = games[_gameId];
        require(game.status == GameStatus.IN_PROGRESS || game.status == GameStatus.DISPUTED, "Game not in disputable state");
        
        if (_refundBoth) {
            // Refund both players
            payable(game.creator).transfer(game.betAmount);
            payable(game.opponent).transfer(game.betAmount);
            game.status = GameStatus.CANCELLED;
        } else {
            game.status = GameStatus.DISPUTED;
        }
    }
}
