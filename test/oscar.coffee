###################################################################
# Setup the tests
###################################################################
should = require 'should'
sinon = require 'sinon'
whenLib = require 'when'
{EventEmitter} = require 'events'

# Client = require '../src/client'
Oscar = require '../src/oscar'
MongoClient = require '../src/modules/mongoClient'
SlackClient = require '../src/modules/slackClient'

###################################################################
# Helper
###################################################################

describe 'oscar', ->

  mongo = new MongoClient()
  slack = new SlackClient()

  # slack stubs, because these methods are unit tested elsewhere
  sendMessageStub = sinon.stub slack, 'sendMessage'
  getUserStub = sinon.stub slack, 'getUser'
  getUserIdsStub = sinon.stub slack, 'getUserIds'
  isUserCommentAllowedStub = sinon.stub slack, 'isUserCommentAllowed'
  disallowUserCommentStub = sinon.stub slack, 'disallowUserComment'

  # mongo stubs
  userExistsStub = sinon.stub mongo, 'userExists'
  saveUserStub = sinon.stub mongo, 'saveUser'
  getLatestUserTimestampStub = sinon.stub mongo, 'getLatestUserTimestampForProperty'
  saveUserStatusStub = sinon.stub mongo, 'saveUserStatus'
  getLatestUserFeedbackStub = sinon.stub mongo, 'getLatestUserFeedback'
  getAllUserFeedback = sinon.stub mongo, 'getAllUserFeedback'
  saveUserFeedbackStub = sinon.stub mongo, 'saveUserFeedback'
  saveUserFeedbackMessageStub = sinon.stub mongo, 'saveUserFeedbackMessage'

  # stub promises
  userExistsStub.returns(whenLib false)
  saveUserStub.returns(whenLib false)
  getLatestUserTimestampStub.returns(whenLib false)

  oscar = new Oscar(mongo, slack)

  # oscar stub
  composeMessageStub = sinon.stub oscar, 'composeMessage'

  # timestamps
  today = Date.now()
  yesterday = today - (3600 * 1000 * 21)

  describe 'presenceHandler', ->

    it 'should save a non-existing user in mongo', (done) ->
      data =
        userId: 'user1'

      oscar.presenceHandler data
      setTimeout ->
        saveUserStub.called.should.be.equal true
        done()
      , 100

    describe 'requestFeedback', ->

      data =
        userId: 'user1'
        status: 'active'

      beforeEach ->
        composeMessageStub.reset()

      it 'should request feedback from an existing user if timestamp expired', (done) ->

        oscar.presenceHandler data
        getLatestUserTimestampStub.returns(whenLib yesterday)

        setTimeout ->
          composeMessageStub.called.should.be.equal true
          composeMessageStub.args[0][0].should.be.equal 'user1'
          composeMessageStub.args[0][1].should.be.equal 'requestFeedback'
          done()
        , 100

      it 'should not request feedback from an existing user if timestamp not expired', (done) ->

        oscar.presenceHandler data
        getLatestUserTimestampStub.returns(whenLib today)

        setTimeout ->
          composeMessageStub.called.should.be.equal false
          done()
        , 100

      it 'should not request feedback from an existing user if status is not active or triggered', (done) ->

        data.status = 'away'
        oscar.presenceHandler data
        getLatestUserTimestampStub.returns(whenLib yesterday)

        setTimeout ->
          composeMessageStub.called.should.be.equal false
          done()
        , 100

  describe 'messageHandler', ->

    beforeEach ->
      composeMessageStub.reset()
      saveUserFeedbackStub.reset()

    it 'should reveal status for a user', (done) ->

      message =
        text: 'How is <@USER2>?'
        user: 'user1'

      targetUserObj =
        id: 'USER2',
        name: 'matt'

      res =
        feedback: 'good'

      getUserStub.returns(targetUserObj)
      getLatestUserFeedbackStub.returns(whenLib res)

      oscar.messageHandler message
      setTimeout ->
        composeMessageStub.args[0][0].should.be.equal('user1')
        composeMessageStub.args[0][1].should.be.equal('userStatus')
        composeMessageStub.args[0][2].feedback.should.be.equal(res.feedback)
        composeMessageStub.args[0][2].user.should.be.equal(targetUserObj)
        done()
      , 100

    it 'should reveal status for the channel', (done) ->

      message =
        text: 'How is <@channel>?'
        user: 'user1'

      res =
        0:
          id: 'user2'
          feedback: 'good'
        1:
          id: 'user3'
          feedback: 'bad'

      targetUserIds = [2, 3]

      getUserIdsStub.returns(targetUserIds)
      getAllUserFeedback.returns(whenLib res)

      oscar.messageHandler message
      setTimeout ->
        composeMessageStub.args[0][1].should.be.equal('channelStatus')
        composeMessageStub.args[0][2].should.be.equal(res)
        done()
      , 100

    it 'should save user feedback message', (done) ->

      message =
        text: '7'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib yesterday)

      oscar.messageHandler message

      setTimeout ->
        saveUserFeedbackStub.called.should.be.equal true
        composeMessageStub.args[0][1].should.be.equal 'feedbackReceived'
        done()
      , 100

    it 'should not allow feedback if already submitted', (done) ->

      message =
        text: '7'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib today)

      oscar.messageHandler message

      setTimeout ->
        saveUserFeedbackStub.called.should.be.equal false
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'alreadySubmitted'
        done()
      , 100

    it 'should not allow invalid feedback', (done) ->

      message =
        text: 'something'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib yesterday)

      oscar.messageHandler message

      setTimeout ->
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'invalidInput'
        done()
      , 100

    it 'should ask user for feedback message if feedback low', (done) ->

      message =
        text: '3'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib yesterday)

      oscar.messageHandler message

      setTimeout ->
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'lowFeedback'
        done()
      , 100

    it 'should thank the user for feedback message if feedback allowed, save feedback to mongo and disallow comment', (done) ->

      message =
        text: 'not feeling so well'
        user: 'user1'

      isUserCommentAllowedStub.returns(whenLib true)

      oscar.messageHandler message

      setTimeout ->
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'feedbackMessageReceived'
        saveUserFeedbackMessageStub.called.should.be.equal true
        disallowUserCommentStub.called.should.be.equal true
        done()
      , 100