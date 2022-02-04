const { assert } = require("chai");
const Artwork = artifacts.require("./Artwork.sol");
require("chai").use(require("chai-as-promised")).should();

contract("Artwork", ([deployer, author, donator]) => {
  let artworkContract;
  before(async () => {
    artworkContract = await Artwork.deployed();
  });

  describe("deployment", () => {
    it("should be an instance of Artwork", async () => {
      const address = await artworkContract.address;
      assert.notEqual(address, null);
      assert.notEqual(address, 0x0);
      assert.notEqual(address, "");
      assert.notEqual(address, undefined);
    });
  });

  describe("NFT", () => {
    let result;
    const hash = "abcd1234";
    let imageCount;
    before( async () => {
      result = await artworkContract.mint(hash, { from: author, });
      imageCount = await artworkContract.tokenCounter();
    });
    it("NFT minted successfully", async () => {
      let nft = await artworkContract.artwork(0);
      assert.equal(imageCount, 1);
      assert.equal(nft.id, 0);
      const uri = await artworkContract.tokenURI(nft.id);
      assert.equal(uri, hash);
    });
    it("Allows users to donate", async () => {
      let oldAuthorBalance;
      oldAuthorBalance = await web3.eth.getBalance(author);
      oldAuthorBalance = new web3.utils.BN(oldAuthorBalance);
      result = await artworkContract.donateToArtOwner(imageCount, {
        from: donator,
        value: web3.utils.toWei("1", "Ether"),
      });
      let newAuthorBalance;
      newAuthorBalance = await web3.eth.getBalance(author);
      newAuthorBalance = new web3.utils.BN(newAuthorBalance);
      let donateImageOwner;
      donateImageOwner = web3.utils.toWei("1", "Ether");
      donateImageOwner = new web3.utils.BN(donateImageOwner);
      const expectedBalance = oldAuthorBalance.add(donateImageOwner);
      assert.equal(newAuthorBalance.toString(), expectedBalance.toString());
    });

  });
});
