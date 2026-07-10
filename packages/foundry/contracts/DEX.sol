// SPDX-License-Identifier: MIT
pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DEX {
    /////////////////
    /// Errors //////
    /////////////////

    // Errors go here
    error DexAlreadyInitialized();
    error TokenTransferFailed();
    error InvalidEthAmount();
    error InvalidTokenAmount();
    error InsufficientTokenBalance(uint256 available, uint256 required);
    error InsufficientTokenAllowance(uint256 available, uint256 required);
    error EthTransferFailed(address to, uint256 amount);
    error InsufficientLiquidity(uint256 available, uint256 required);

    //////////////////////
    /// State Variables //
    //////////////////////

    IERC20 public immutable token;
    uint256 public totalLiquidity;
    mapping(address => uint256) liquidity;

    ////////////////
    /// Events /////
    ////////////////

    // Events go here...
    event EthToTokenSwap(
        address swapper,
        uint256 tokenOutput,
        uint256 ethInput
    );
    event TokenToEthSwap(
        address swapper,
        uint256 tokensInput,
        uint256 ethOutput
    );

    event LiquidityProvided(
        address liquidityProvider,
        uint256 liquidityMinted,
        uint256 ethInput,
        uint256 tokensInput
    );
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 liquidityWithdrawn,
        uint256 tokensOutput,
        uint256 ethOutput
    );
    ///////////////////
    /// Constructor ///
    ///////////////////

    constructor(address tokenAddr) {
        token = IERC20(tokenAddr);
    }

    ///////////////////
    /// Functions /////
    ///////////////////

    function init(
        uint256 tokens
    ) public payable returns (uint256 initialLiquidity) {
        if (totalLiquidity != 0) revert DexAlreadyInitialized();
        totalLiquidity = msg.value;
        liquidity[msg.sender] = totalLiquidity;
        initialLiquidity = totalLiquidity;
        (bool success) = token.transferFrom(msg.sender, address(this), tokens);
        if (!success) revert TokenTransferFailed();
    }

    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public pure returns (uint256 yOutput) {
        // Your code here...
        uint256 xInputWithFee = (xInput * 997) / 1000; //txn fee is 0.3%
        yOutput = (xInputWithFee * yReserves) / (xReserves + xInputWithFee);
        return yOutput;
    }

    function getLiquidity(
        address lp
    ) public view returns (uint256 lpLiquidity) {
        return liquidity[lp];
    }

    function ethToToken() public payable returns (uint256 tokenOutput) {
        if (msg.value == 0) revert InvalidEthAmount();
        uint256 ethInput = msg.value;

        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance - msg.value;
        tokenOutput = price(ethInput, ethReserve, tokenReserve);
        if (tokenReserve < tokenOutput)
            revert InsufficientTokenBalance(tokenReserve, tokenOutput);

        (bool success) = token.transfer(msg.sender, tokenOutput);
        if (!success) revert TokenTransferFailed();
        emit EthToTokenSwap(msg.sender, tokenOutput, ethInput);
    }

    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        if (tokenInput == 0) revert InvalidTokenAmount();
        uint256 bal = token.balanceOf(msg.sender);
        if (bal < tokenInput) revert InsufficientTokenBalance(bal, tokenInput);
        uint256 allow = token.allowance(msg.sender, address(this));
        if (allow < tokenInput)
            revert InsufficientTokenAllowance(allow, tokenInput);
        uint256 tokenReserve = token.balanceOf(address(this));
        ethOutput = price(tokenInput, tokenReserve, address(this).balance);
        if (!token.transferFrom(msg.sender, address(this), tokenInput))
            revert TokenTransferFailed();
        (bool sent, ) = msg.sender.call{value: ethOutput}("");
        if (!sent) revert EthTransferFailed(msg.sender, ethOutput);
        emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
        return ethOutput;
    }

    function deposit() public payable returns (uint256 tokensDeposited) {
        if (msg.value == 0) revert InvalidEthAmount();
        uint256 allow = token.allowance(msg.sender, address(this));

        uint256 ethInput = msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance - msg.value;

        //caluclated using LP minted = (amount added / reserve before deposit) × total LP supply coul also be LP minted = ΔTOKEN × S / RTOKEN since both eth and tokens are both added in correct ratio
        uint256 liquidityMinted = (ethInput * totalLiquidity) / ethReserve;

        totalLiquidity += liquidityMinted;
        liquidity[msg.sender] += liquidityMinted;
        tokensDeposited = (ethInput * tokenReserve) / ethReserve;

        if (allow < tokensDeposited)
            revert InsufficientTokenAllowance(allow, tokensDeposited);

        if (!token.transferFrom(msg.sender, address(this), tokensDeposited))
            revert TokenTransferFailed();
        emit LiquidityProvided(
            msg.sender,
            liquidityMinted,
            ethInput,
            tokensDeposited
        );
    }

    function withdraw(
        uint256 amount
    ) public returns (uint256 ethAmount, uint256 tokenAmount) {
        if (amount > liquidity[msg.sender]) {
            revert InsufficientLiquidity(liquidity[msg.sender], amount);
        }
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance ;
        ethAmount = (amount * ethReserve) / totalLiquidity;
        tokenAmount = (amount * tokenReserve) / totalLiquidity;
        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");

        if (!success) revert EthTransferFailed(msg.sender, ethAmount);
        if (!token.transfer(msg.sender, tokenAmount))
            revert TokenTransferFailed();

        emit LiquidityRemoved(msg.sender, amount, tokenAmount, ethAmount);
    }
}
