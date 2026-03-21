// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TempoMemeToken is ERC20 {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
    {
        _mint(msg.sender, 1_000_000_000 * 10**18);
    }
}

contract TempoUSDCLaunch is Ownable, ReentrancyGuard {

    IERC20 public immutable USDC;

    uint256 public constant FEE = 100;           // 1%
    uint256 public constant FEE_DENOM = 10000;
    uint256 public constant TARGET_RAISE = 12_000 * 1e6; // 12,000 USDC
    uint256 public constant INITIAL_PRICE = 1e12;

    struct Launch {
        address token;
        address creator;
        uint256 raised;
        bool graduated;
    }

    mapping(address => Launch) public launches;
    mapping(address => bool) public isLaunch;

    event LaunchCreated(address indexed token, address indexed creator, string name);
    event TokenBought(address indexed token, address indexed buyer, uint256 usdcIn, uint256 tokensOut);
    event LaunchGraduated(address indexed token);

    constructor(address _usdc) Ownable(msg.sender) {
        USDC = IERC20(_usdc);
    }

    function createLaunch(string memory name, string memory symbol) external returns (address) {
        TempoMemeToken token = new TempoMemeToken(name, symbol);
        address tokenAddr = address(token);

        launches[tokenAddr] = Launch({
            token: tokenAddr,
            creator: msg.sender,
            raised: 0,
            graduated: false
        });

        isLaunch[tokenAddr] = true;

        emit LaunchCreated(tokenAddr, msg.sender, name);
        return tokenAddr;
    }

    function buy(address tokenAddr, uint256 usdcAmount) external nonReentrant {
        require(isLaunch[tokenAddr], "Invalid launch");
        Launch storage l = launches[tokenAddr];
        require(!l.graduated, "Already graduated");

        uint256 fee = (usdcAmount * FEE) / FEE_DENOM;
        uint256 afterFee = usdcAmount - fee;

        require(USDC.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        uint256 price = getPrice(tokenAddr);
        uint256 tokensOut = (afterFee * 1e18) / price;

        IERC20(tokenAddr).transfer(msg.sender, tokensOut);
        l.raised += afterFee;

        emit TokenBought(tokenAddr, msg.sender, usdcAmount, tokensOut);

        if (l.raised >= TARGET_RAISE) {
            l.graduated = true;
            emit LaunchGraduated(tokenAddr);
        }
    }

    function getPrice(address tokenAddr) public view returns (uint256) {
        uint256 raised = launches[tokenAddr].raised;
        if (raised == 0) return INITIAL_PRICE;
        uint256 progress = (raised * 1e18) / TARGET_RAISE;
        return INITIAL_PRICE + (progress ** 2) / 7e10;
    }

    function withdrawFees() external onlyOwner {
        USDC.transfer(owner(), USDC.balanceOf(address(this)));
    }
}
