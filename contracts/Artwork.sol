// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Artwork is ERC721 {

  uint256 public tokenCounter;
  uint256 public contributorCounter = 0;

  // data structure to store art data
  struct Art {
    uint256 id;
    string URI;
    uint256 donationAmount;
    address payable author;
  }

  // mapping to store URIs from IPFS
  mapping (uint256 => string) private _tokenURIs;
  // mapping to store art struct data
  mapping (uint256 => Art) public artwork;
  // mapping to track donators/contributors
  mapping (address => uint256) public contributors;

  // Event emitted when art is created
  event artCreated(
    uint256 id,
    string URI,
    uint256 donationAmount,
    address payable author
  );

  // Event emitted when there is a donation
  event donateToArt(
    uint256 id,
    string URI,
    uint256 donationAmount,
    address payable author
  );

  constructor(
    string memory name,
    string memory symbol
  ) ERC721(name, symbol) {
    tokenCounter = 0;
  }

  function mint(string memory _tokenURI) public {
    _safeMint(msg.sender, tokenCounter);
    _setTokenURI(tokenCounter, _tokenURI);

    artwork[tokenCounter] = Art(
      tokenCounter,
      _tokenURI,
      0,
      payable(msg.sender)
    );
    emit artCreated(tokenCounter, _tokenURI, 0, payable(msg.sender));
    tokenCounter++;
  }

  function _setTokenURI(uint256 _tokenId, string memory _tokenURI) internal virtual {
    // Checks if tokenId exists
    require( _exists(_tokenId), "ERC721Metadata: URI set of nonexistent token.");
    _tokenURIs[_tokenId] = _tokenURI;
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns(string memory) {
    require( _exists(_tokenId), "ERC721Metadata: URI set of nonexistent token.");
    return _tokenURIs[_tokenId];
  }

  function donateToArtOwner(uint256 _id) public payable {
    require(_id > 0 && _id <= tokenCounter);

    Art memory _art = artwork[_id];
    address payable _author = _art.author;
    payable(address(_author)).transfer(msg.value);
    _art.donationAmount = _art.donationAmount + msg.value;
    artwork[_id] = _art;

    // store address of contributor for future royalties
    contributors[msg.sender] = contributorCounter;
    contributorCounter++;

    emit donateToArt(_id, _art.URI, _art.donationAmount, _author);
  }

}
