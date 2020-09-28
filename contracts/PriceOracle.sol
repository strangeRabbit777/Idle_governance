pragma solidity 0.6.12;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IdleToken.sol";
import "./interfaces/CERC20.sol";
import "./interfaces/Comptroller.sol";
import "./interfaces/ChainLinkOracle.sol";

import "./lib/Exponential.sol";

contract PriceOracle is Ownable, Exponential {
  using SafeMath for uint256;

  address constant private ONE = 10**18;
  address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address constant public COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

  uint256 public blocksPerYear = 2371428; // -> blocks per year with ~13.3s block time
  // underlying -> chainlink feed
  mapping (address => address) priceFeedsUSD;
  mapping (address => address) priceFeedsETH;

  constructor() public {
    priceFeedsUSD[WETH] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // WETH
    priceFeedsUSD[COMP] = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5; // COMP
    priceFeedsUSD[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // wBTC
    priceFeedsUSD[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9; // DAI

    priceFeedsETH[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0xdeb288F737066589598e9214E782fa5A8eD689e8; // wBTC
    priceFeedsETH[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0x773616E4d11A78F511299002da57A0a94577F1f4; // DAI
    priceFeedsETH[0x57Ab1ec28D129707052df4dF418D58a2D46d5f51] = 0x8e0b7e6062272B5eF4524250bFFF8e5Bd3497757; // SUSD
    priceFeedsETH[0x0000000000085d4780B73119b644AE5ecd22b376] = 0x3886BA987236181D98F2401c507Fb8BeA7871dF2; // TUSD
    priceFeedsETH[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4; // USDC
    priceFeedsETH[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46; // USDT
  }

  function getPriceUSD(address _asset) public view returns (uint256) {
    return _getPriceUSD(_asset); // 1e18
  }
  function getPriceETH(address _asset) public view returns (uint256) {
    return _getPriceETH(_asset); // 1e18
  }
  function getPriceToken(address _asset, address _token) public view returns (uint256) {
    return _getPriceToken(_asset, _token); // 1e(_token.decimals())
  }
  function getUnderlyingPrice(address _idleToken) external view returns (uint256) {
    return getPriceUSD(IdleToken(_idleToken).token()); // 1e8
  }
  function getCompApr(address cToken) external view returns (uint256) {
    CERC20 _ctoken = CERC20(cToken);
    uint256 compSpeeds = Comptroller(_ctoken.comptroller()).compSpeeds(cToken);
    uint256 cTokenNAV = _ctoken.exchangeRateStored().mul(IERC20(cToken).totalSupply()).div(ONE_18);
    // how much costs 1COMP in token (1e(_token.decimals()))
    uint256 compUnderlyingPrice = getPriceToken(COMP, token);
    return compSpeeds.mul(compUnderlyingPrice).mul(blocksPerYear).div(cTokenNAV).mul(100);
  }

  // #### internal
  function _getPriceUSD(address _asset) internal view returns (uint256 price) {
    if (priceFeedsUSD[_asset] != address(0)) {
      price = ChainLinkOracle(priceFeedsUSD[_asset]).latestAnswer().times(10**10); // scale it to 1e18
    } else if (priceFeedsETH[_asset] != address(0)) {
      price = ChainLinkOracle(priceFeedsETH[_asset]).latestAnswer();
      price = _price.mul(ChainLinkOracle(priceFeedsUSD[WETH]).latestAnswer().times(10**10)).div(ONE);
    }
  }
  function _getPriceETH(address _asset) internal view returns (uint256 price) {
    if (priceFeedsETH[_asset] != address(0)) {
      price = ChainLinkOracle(priceFeedsETH[_asset]).latestAnswer();
    }
  }
  function _getPriceToken(address _asset, address _token) internal view returns (uint256 price) {
    uint256 assetUSD = getPriceUSD(_asset)
    uint256 tokenUSD = getPriceUSD(_token);
    return assetUSD.times(10**(ERC20(_token).decimals())).div(tokenUSD); // 1e(tokenDecimals)
  }

  // #### onlyOwner
  function setBlocksPerYear(uint256 _blocksPerYear) external onlyOwner {
    blocksPerYear = _blocksPerYear;
  }

  // _feed can be address(0) which means disabled
  function updateFeedETH(address _asset, address _feed) external onlyOwner {
    priceFeedsETH[_asset] = _feed;
  }
  function updateFeedUSD(address _asset, address _feed) external onlyOwner {
    priceFeedsUSD[_asset] = _feed;
  }
}
